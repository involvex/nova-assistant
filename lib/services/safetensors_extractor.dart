import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal safetensors reader/extractor for the Z-Image host assets.
///
/// Format (https://github.com/huggingface/safetensors):
/// `[u64 LE headerLen][JSON header][tensor bytes]`. Each header entry is
/// `{dtype, shape, data_offsets: [start, end]}` relative to the data
/// section; `__metadata__` (if present) is ignored.
///
/// Only what the extractor needs is implemented — no strided views, no
/// device mapping. All copies are chunked so a 778 MB matrix never sits
/// fully in memory alongside its source.
class SafetensorsTensorEntry {
  const SafetensorsTensorEntry({
    required this.dtype,
    required this.shape,
    required this.start,
    required this.end,
  });

  final String dtype;
  final List<int> shape;
  final int start;
  final int end;

  int get byteLength => end - start;

  static const Map<String, int> bytesPerElement = <String, int>{
    'BOOL': 1,
    'U8': 1,
    'I8': 1,
    'I16': 2,
    'U16': 2,
    'F16': 2,
    'BF16': 2,
    'I32': 4,
    'U32': 4,
    'F32': 4,
    'F64': 8,
    'I64': 8,
    'U64': 8,
  };
}

class SafetensorsHeader {
  const SafetensorsHeader({required this.entries, required this.dataStart});

  final Map<String, SafetensorsTensorEntry> entries;

  /// Absolute file offset where the data section begins.
  final int dataStart;
}

/// Parses the header of [source]. Throws [FormatException] on truncated
/// files, oversized headers, or invalid JSON.
Future<SafetensorsHeader> readSafetensorsHeader(
  File source, {
  int maxHeaderBytes = 32 * 1024 * 1024,
}) async {
  final RandomAccessFile raf = await source.open(mode: FileMode.read);
  try {
    final int fileLength = await raf.length();
    if (fileLength < 8) {
      throw const FormatException('File too short for safetensors header');
    }
    final Uint8List lenBytes = Uint8List.fromList(await raf.read(8));
    final int headerLen = ByteData.sublistView(lenBytes)
        .getUint64(0, Endian.little);
    if (headerLen <= 0 || headerLen > maxHeaderBytes) {
      throw FormatException(
        'Implausible safetensors header length: $headerLen',
      );
    }
    if (8 + headerLen > fileLength) {
      throw const FormatException('Truncated safetensors header');
    }
    final Uint8List jsonBytes = Uint8List.fromList(await raf.read(headerLen));
    if (jsonBytes.length != headerLen) {
      throw const FormatException('Truncated safetensors header');
    }
    return parseSafetensorsHeaderJson(jsonBytes, dataStart: 8 + headerLen);
  } finally {
    await raf.close();
  }
}

/// Parses the JSON header section of a safetensors file into tensor entries.
///
/// Shared by the local ([readSafetensorsHeader]) and ranged-HTTP
/// ([readRemoteSafetensorsHeader]) readers so both agree on validation —
/// in particular the offsets-vs-shape size check, which is what catches a
/// truncated or mismatched shard.
SafetensorsHeader parseSafetensorsHeaderJson(
  Uint8List jsonBytes, {
  required int dataStart,
}) {
  final Object? decoded = jsonDecode(utf8.decode(jsonBytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Safetensors header is not a JSON object');
  }
  final Map<String, SafetensorsTensorEntry> entries =
      <String, SafetensorsTensorEntry>{};
  decoded.forEach((String name, Object? raw) {
    if (name == '__metadata__') return;
    if (raw is! Map<String, Object?>) {
      throw FormatException('Bad entry for tensor "$name"');
    }
    final Object? dtype = raw['dtype'];
    final Object? shape = raw['shape'];
    final Object? offsets = raw['data_offsets'];
    if (dtype is! String ||
        shape is! List ||
        offsets is! List ||
        offsets.length != 2) {
      throw FormatException('Bad entry for tensor "$name"');
    }
    final List<int> shapeInts = <int>[];
    for (final Object? dim in shape) {
      if (dim is! int || dim < 0) {
        throw FormatException('Bad shape for tensor "$name"');
      }
      shapeInts.add(dim);
    }
    final Object? start = offsets[0];
    final Object? end = offsets[1];
    if (start is! int || end is! int || start < 0 || end < start) {
      throw FormatException('Bad data_offsets for tensor "$name"');
    }
    final int? bpe = SafetensorsTensorEntry.bytesPerElement[dtype];
    if (bpe == null) {
      throw FormatException('Unknown dtype "$dtype" for tensor "$name"');
    }
    final int elements = shapeInts.isEmpty
        ? 1
        : shapeInts.fold<int>(1, (int a, int b) => a * b);
    if ((end - start) != elements * bpe) {
      throw FormatException(
        'Size mismatch for tensor "$name": offsets say ${end - start} '
        'bytes but $dtype$shapeInts needs ${elements * bpe}',
      );
    }
    entries[name] = SafetensorsTensorEntry(
      dtype: dtype,
      shape: shapeInts,
      start: start,
      end: end,
    );
  });
  return SafetensorsHeader(entries: entries, dataStart: dataStart);
}

/// Copies [names] (`source key` → `dest key`) from [source] into a new
/// safetensors file at [dest], rebasing data offsets. Missing source keys
/// throw [StateError]. Parent directories of [dest] are created.
Future<void> extractSafetensorsTensors({
  required File source,
  required Map<String, String> names,
  required File dest,
  int copyChunkBytes = 4 * 1024 * 1024,
}) async {
  if (names.isEmpty) {
    throw ArgumentError('names must not be empty');
  }
  final SafetensorsHeader header = await readSafetensorsHeader(source);
  for (final String src in names.keys) {
    if (!header.entries.containsKey(src)) {
      throw StateError(
        'Tensor "$src" not found in ${source.path} '
        '(${header.entries.length} tensors available)',
      );
    }
  }

  await _writeDerivedSafetensors(
    header: header,
    names: names,
    dest: dest,
    copy: (String src, int length, RandomAccessFile append) async {
      final RandomAccessFile handle = await source.open(mode: FileMode.read);
      try {
        final SafetensorsTensorEntry entry = header.entries[src]!;
        await handle.setPosition(header.dataStart + entry.start);
        int remaining = length;
        int written = 0;
        // Stream chunk-by-chunk: buffering here would hold the full 778 MB
        // embed_tokens matrix in the Dart heap.
        while (remaining > 0) {
          final int want = remaining < copyChunkBytes
              ? remaining
              : copyChunkBytes;
          final Uint8List chunk = Uint8List.fromList(await handle.read(want));
          if (chunk.isEmpty) {
            throw const FormatException(
              'Truncated tensor data during extraction',
            );
          }
          await append.writeFrom(chunk);
          written += chunk.length;
          remaining -= chunk.length;
        }
        if (written != length) {
          throw FormatException(
            'Short read for tensor "$src": expected $length, got $written',
          );
        }
      } finally {
        await handle.close();
      }
    },
  );
}

/// Writes a derived safetensors file containing [names] from [header].
///
/// [copy] streams one source tensor straight into [append], so neither the
/// local nor the remote path ever holds a whole 778 MB matrix in memory.
/// Shared so both paths emit byte-identical layout: a fresh header with
/// offsets rebased to 0, then tensor data in insertion order.
Future<void> _writeDerivedSafetensors({
  required SafetensorsHeader header,
  required Map<String, String> names,
  required File dest,
  required Future<void> Function(
    String src,
    int length,
    RandomAccessFile append,
  )
  copy,
  int copyChunkBytes = 4 * 1024 * 1024,
}) async {
  final Map<String, Object> destHeader = <String, Object>{};
  int cursor = 0;
  final List<({String src, int length})> plan = <({String src, int length})>[];
  names.forEach((String src, String dst) {
    final SafetensorsTensorEntry entry = header.entries[src]!;
    destHeader[dst] = <String, Object>{
      'dtype': entry.dtype,
      'shape': entry.shape,
      'data_offsets': <int>[cursor, cursor + entry.byteLength],
    };
    cursor += entry.byteLength;
    plan.add((src: src, length: entry.byteLength));
  });

  final List<int> headerJson = utf8.encode(jsonEncode(destHeader));
  await dest.parent.create(recursive: true);
  final RandomAccessFile out = await dest.open(mode: FileMode.write);
  try {
    final ByteData lenPrefix = ByteData(8)
      ..setUint64(0, headerJson.length, Endian.little);
    await out.writeFrom(lenPrefix.buffer.asUint8List());
    await out.writeFrom(headerJson);
  } finally {
    await out.close();
  }

  final RandomAccessFile append = await dest.open(mode: FileMode.append);
  try {
    for (final ({String src, int length}) job in plan) {
      await copy(job.src, job.length, append);
    }
  } finally {
    await append.close();
  }
}

// ---------------------------------------------------------------- ranged HTTP

/// Thrown when the server does not honour `Range` requests.
class RangeNotSupportedException implements Exception {
  const RangeNotSupportedException(this.uri);
  final Uri uri;
  @override
  String toString() => 'Server does not support byte ranges: $uri';
}

/// Reads a byte range `[start, end]` (inclusive) from [uri].
///
/// Throws [RangeNotSupportedException] when the response is a full `200`
/// body rather than a `206` partial — silently accepting that would either
/// buffer a multi-GB shard or write garbage into the derived file.
Future<Uint8List> readByteRange({
  required Uri uri,
  required int start,
  required int end,
  String? token,
  HttpClient? client,
  bool ownClient = false,
}) async {
  final HttpClient http = client ?? HttpClient();
  if (ownClient || client == null) {
    http.connectionTimeout = const Duration(seconds: 30);
  }
  try {
    final HttpClientRequest req = await http.getUrl(uri);
    if (token != null && token.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final HttpClientResponse res = await req.close();

    if (res.statusCode != HttpStatus.partialContent) {
      await res.drain<void>();
      if (res.statusCode == HttpStatus.ok) {
        throw RangeNotSupportedException(uri);
      }
      throw HttpException(
        'HTTP ${res.statusCode} for range $start-$end of $uri',
        uri: uri,
      );
    }
    // A single range is bounded (≤ copyChunkBytes), so buffering it is safe.
    // HttpClientResponse is a Stream<List<int>>; its join() returns a String
    // (ByteStream override), hence the explicit collector.
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in res) {
      builder.add(chunk);
    }
    final Uint8List bytes = builder.takeBytes();
    final int want = end - start + 1;
    if (bytes.length != want) {
      throw HttpException(
        'Short range read: wanted $want bytes, got ${bytes.length}',
        uri: uri,
      );
    }
    return bytes;
  } finally {
    if (ownClient || client == null) {
      http.close(force: true);
    }
  }
}

/// Reads a remote safetensors header with two ranged requests instead of
/// downloading the file: 8 bytes for the length prefix, then the JSON.
Future<SafetensorsHeader> readRemoteSafetensorsHeader({
  required Uri uri,
  String? token,
  HttpClient? client,
  bool ownClient = false,
  int maxHeaderBytes = 32 * 1024 * 1024,
}) async {
  final Uint8List lenBytes = await readByteRange(
    uri: uri,
    start: 0,
    end: 7,
    token: token,
    client: client,
    ownClient: ownClient,
  );
  final int headerLen = ByteData.sublistView(lenBytes)
      .getUint64(0, Endian.little);
  if (headerLen <= 0 || headerLen > maxHeaderBytes) {
    throw FormatException('Implausible safetensors header length: $headerLen');
  }
  final Uint8List jsonBytes = await readByteRange(
    uri: uri,
    start: 8,
    end: 8 + headerLen - 1,
    token: token,
    client: client,
    ownClient: ownClient,
  );
  return parseSafetensorsHeaderJson(jsonBytes, dataStart: 8 + headerLen);
}

/// Extracts [names] from the remote safetensors at [uri] by ranged reads.
///
/// Transfers only the selected tensors rather than the whole shard, which is
/// the difference between ~780 MB and several GB for the Z-Image host
/// assets. Requires a server that honours `Range`.
Future<void> extractSafetensorsTensorsRemote({
  required Uri uri,
  required Map<String, String> names,
  required File dest,
  String? token,
  HttpClient? client,
  bool ownClient = false,
  SafetensorsHeader? header,
  void Function(int received, int total)? onProgress,
  int copyChunkBytes = 8 * 1024 * 1024,
}) async {
  if (names.isEmpty) {
    throw ArgumentError('names must not be empty');
  }
  final HttpClient http = client ?? HttpClient();
  final bool owns = ownClient || client == null;
  if (owns) http.connectionTimeout = const Duration(seconds: 30);
  try {
    // Callers that already validated the header (dtype/shape gate before
    // transferring ~780 MB) pass it in to avoid a second fetch.
    final SafetensorsHeader hdr =
        header ??
        await readRemoteSafetensorsHeader(uri: uri, token: token, client: http);
    for (final String src in names.keys) {
      if (!hdr.entries.containsKey(src)) {
        throw StateError(
          'Tensor "$src" not found in $uri '
          '(${hdr.entries.length} tensors available)',
        );
      }
    }

    final int total = names.keys.fold<int>(
      0,
      (int sum, String src) => sum + hdr.entries[src]!.byteLength,
    );
    int received = 0;

    await _writeDerivedSafetensors(
      header: hdr,
      names: names,
      dest: dest,
      copyChunkBytes: copyChunkBytes,
      copy: (String src, int length, RandomAccessFile append) async {
        final SafetensorsTensorEntry entry = hdr.entries[src]!;
        final int absStart = hdr.dataStart + entry.start;
        int fetched = 0;
        // Stream straight to disk; never accumulate the range in the heap.
        while (fetched < length) {
          final int want = length - fetched < copyChunkBytes
              ? length - fetched
              : copyChunkBytes;
          final Uint8List chunk = await readByteRange(
            uri: uri,
            start: absStart + fetched,
            end: absStart + fetched + want - 1,
            token: token,
            client: http,
          );
          await append.writeFrom(chunk);
          fetched += chunk.length;
          received += chunk.length;
          onProgress?.call(received, total);
        }
      },
    );
    onProgress?.call(total, total);
  } finally {
    if (owns) http.close(force: true);
  }
}

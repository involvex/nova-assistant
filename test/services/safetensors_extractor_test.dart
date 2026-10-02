import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/safetensors_extractor.dart';
import 'package:nova_assistant/services/zimage_tensor_extraction.dart';
import 'package:nova_assistant/utils/file_hash.dart';

/// Writes a synthetic safetensors file. Each tensor gets zero-filled bytes
/// sized by dtype+shape.
Future<File> writeSafetensors(
  Directory dir,
  String name,
  Map<String, ({String dtype, List<int> shape})> tensors,
) async {
  final Map<String, Object> header = <String, Object>{};
  int cursor = 0;
  final Map<String, int> lengths = <String, int>{};
  tensors.forEach((String key, ({String dtype, List<int> shape}) spec) {
    final int bpe = SafetensorsTensorEntry.bytesPerElement[spec.dtype]!;
    final int elements = spec.shape.isEmpty
        ? 1
        : spec.shape.fold<int>(1, (int a, int b) => a * b);
    final int len = elements * bpe;
    header[key] = <String, Object>{
      'dtype': spec.dtype,
      'shape': spec.shape,
      'data_offsets': <int>[cursor, cursor + len],
    };
    lengths[key] = len;
    cursor += len;
  });
  final List<int> headerJson = utf8.encode(jsonEncode(header));
  final File file = File('${dir.path}/$name');
  final RandomAccessFile out = await file.open(mode: FileMode.write);
  try {
    final ByteData prefix = ByteData(8)
      ..setUint64(0, headerJson.length, Endian.little);
    await out.writeFrom(prefix.buffer.asUint8List());
    await out.writeFrom(headerJson);
    for (final String key in tensors.keys) {
      int remaining = lengths[key]!;
      final int seed = key.length;
      while (remaining > 0) {
        final int want = remaining < 4096 ? remaining : 4096;
        await out.writeFrom(
          Uint8List.fromList(
            List<int>.generate(want, (int i) => (seed + i) % 256),
          ),
        );
        remaining -= want;
      }
    }
  } finally {
    await out.close();
  }
  return file;
}

void main() {
  group('readSafetensorsHeader', () {
    test('parses entries and data start', () async {
      final dir = await Directory.systemTemp.createTemp('sft_header_');
      try {
        final file = await writeSafetensors(
          dir,
          'a.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'w': (dtype: 'F32', shape: <int>[2, 2]),
            'b': (dtype: 'F32', shape: <int>[2]),
          },
        );
        final header = await readSafetensorsHeader(file);

        expect(header.entries.keys, containsAll(<String>['w', 'b']));
        expect(header.entries['w']!.shape, <int>[2, 2]);
        expect(header.entries['w']!.byteLength, 16);
        expect(header.dataStart, greaterThan(8));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rejects truncated files', () async {
      final dir = await Directory.systemTemp.createTemp('sft_trunc_');
      try {
        final file = File('${dir.path}/bad.safetensors');
        await file.writeAsBytes(<int>[1, 2, 3]);
        await expectLater(readSafetensorsHeader(file), throwsFormatException);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rejects size lies in data_offsets', () async {
      final dir = await Directory.systemTemp.createTemp('sft_lie_');
      try {
        final headerJson = utf8.encode(
          jsonEncode(<String, Object>{
            'w': <String, Object>{
              'dtype': 'F32',
              'shape': <int>[2, 2],
              'data_offsets': <int>[0, 4],
            },
          }),
        );
        final file = File('${dir.path}/lie.safetensors');
        final out = await file.open(mode: FileMode.write);
        try {
          final prefix = ByteData(8)
            ..setUint64(0, headerJson.length, Endian.little);
          await out.writeFrom(prefix.buffer.asUint8List());
          await out.writeFrom(headerJson);
          await out.writeFrom(List<int>.filled(16, 0));
        } finally {
          await out.close();
        }
        await expectLater(readSafetensorsHeader(file), throwsFormatException);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('extractSafetensorsTensors', () {
    test('round-trips a subset with rebased offsets', () async {
      final dir = await Directory.systemTemp.createTemp('sft_extract_');
      try {
        final src = await writeSafetensors(
          dir,
          'src.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'a': (dtype: 'F32', shape: <int>[2, 2]),
            'b': (dtype: 'F32', shape: <int>[3]),
            'c': (dtype: 'I32', shape: <int>[1]),
          },
        );
        final dest = File('${dir.path}/dest.safetensors');
        await extractSafetensorsTensors(
          source: src,
          names: <String, String>{'b': 'kept_b', 'a': 'kept_a'},
          dest: dest,
        );

        final header = await readSafetensorsHeader(dest);
        expect(header.entries.keys, <String>['kept_b', 'kept_a']);
        // Rebased: first tensor starts at 0.
        expect(header.entries['kept_b']!.start, 0);
        expect(header.entries['kept_b']!.end, 12);
        expect(header.entries['kept_a']!.start, 12);

        // Byte-identical payloads.
        final srcHeader = await readSafetensorsHeader(src);
        for (final entry in <String>['kept_b', 'kept_a']) {
          final srcKey = entry == 'kept_b' ? 'b' : 'a';
          final srcRaf = await src.open(mode: FileMode.read);
          final destRaf = await dest.open(mode: FileMode.read);
          try {
            await srcRaf.setPosition(
              srcHeader.dataStart + srcHeader.entries[srcKey]!.start,
            );
            await destRaf.setPosition(
              header.dataStart + header.entries[entry]!.start,
            );
            final srcBytes = await srcRaf.read(
              srcHeader.entries[srcKey]!.byteLength,
            );
            final destBytes = await destRaf.read(
              header.entries[entry]!.byteLength,
            );
            expect(destBytes, srcBytes);
          } finally {
            await srcRaf.close();
            await destRaf.close();
          }
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws on missing source key', () async {
      final dir = await Directory.systemTemp.createTemp('sft_missing_');
      try {
        final src = await writeSafetensors(
          dir,
          'src.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'a': (dtype: 'F32', shape: <int>[1]),
          },
        );
        await expectLater(
          extractSafetensorsTensors(
            source: src,
            names: <String, String>{'nope': 'nope'},
            dest: File('${dir.path}/d.safetensors'),
          ),
          throwsStateError,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('ZImageTensorExtraction.findEmbedTokensKey', () {
    test('finds the single matching entry', () async {
      final dir = await Directory.systemTemp.createTemp('sft_find_');
      try {
        final src = await writeSafetensors(
          dir,
          'enc.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'model.layers.0.weight': (dtype: 'F16', shape: <int>[4, 3]),
            'model.embed_tokens.weight': (dtype: 'F16', shape: <int>[4, 3]),
          },
        );
        expect(
          await ZImageTensorExtraction.findEmbedTokensKey(
            src,
            expectedShape: <int>[4, 3],
          ),
          'model.embed_tokens.weight',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws on zero or ambiguous matches', () async {
      final dir = await Directory.systemTemp.createTemp('sft_amb_');
      try {
        final none = await writeSafetensors(
          dir,
          'none.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'w': (dtype: 'F32', shape: <int>[4, 3]),
          },
        );
        await expectLater(
          ZImageTensorExtraction.findEmbedTokensKey(
            none,
            expectedShape: <int>[4, 3],
          ),
          throwsStateError,
        );

        final two = await writeSafetensors(
          dir,
          'two.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'a.embed_tokens': (dtype: 'F32', shape: <int>[4, 3]),
            'b.embed_tokens': (dtype: 'F32', shape: <int>[4, 3]),
          },
        );
        await expectLater(
          ZImageTensorExtraction.findEmbedTokensKey(
            two,
            expectedShape: <int>[4, 3],
          ),
          throwsStateError,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('ZImageTensorExtraction.extractTEmbedder', () {
    test('extracts the 4 MLP tensors with exact shapes', () async {
      final dir = await Directory.systemTemp.createTemp('sft_temb_');
      try {
        final src = await writeSafetensors(
          dir,
          'trans.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'other': (dtype: 'F32', shape: <int>[2]),
            't_embedder.mlp.0.weight': (dtype: 'F32', shape: <int>[1024, 256]),
            't_embedder.mlp.0.bias': (dtype: 'F32', shape: <int>[1024]),
            't_embedder.mlp.2.weight': (dtype: 'F32', shape: <int>[256, 1024]),
            't_embedder.mlp.2.bias': (dtype: 'F32', shape: <int>[256]),
          },
        );
        final dest = File('${dir.path}/t_embedder.safetensors');
        await ZImageTensorExtraction.extractTEmbedder(source: src, dest: dest);

        final header = await readSafetensorsHeader(dest);
        expect(
          header.entries.keys.toSet(),
          ZImageTensorExtraction.tEmbedderTensors.keys.toSet(),
        );
        expect(header.entries['t_embedder.mlp.0.weight']!.shape, <int>[
          1024,
          256,
        ]);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rejects wrong dtype or shape', () async {
      final dir = await Directory.systemTemp.createTemp('sft_temb_bad_');
      try {
        final src = await writeSafetensors(
          dir,
          'trans.safetensors',
          <String, ({String dtype, List<int> shape})>{
            't_embedder.mlp.0.weight': (dtype: 'F16', shape: <int>[1024, 256]),
            't_embedder.mlp.0.bias': (dtype: 'F32', shape: <int>[1024]),
            't_embedder.mlp.2.weight': (dtype: 'F32', shape: <int>[256, 1024]),
            't_embedder.mlp.2.bias': (dtype: 'F32', shape: <int>[256]),
          },
        );
        await expectLater(
          ZImageTensorExtraction.extractTEmbedder(
            source: src,
            dest: File('${dir.path}/t.safetensors'),
          ),
          throwsStateError,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('sha256HexOfFile', () {
    test('matches the known empty-string digest', () async {
      final dir = await Directory.systemTemp.createTemp('sft_hash_');
      try {
        final file = File('${dir.path}/empty.bin');
        await file.writeAsBytes(<int>[]);
        expect(
          await sha256HexOfFile(file),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('ranged HTTP extraction', () {
    /// Serves [file] with real `Range` support and counts how many bytes it
    /// actually sent, so a test can assert ranged reads never pull the whole
    /// shard. [honourRange] false emulates a server that ignores `Range`.
    Future<({HttpServer server, int Function() bytesSent, int requests})>
    serveFile(File file, {required bool honourRange}) async {
      final Uint8List all = await file.readAsBytes();
      int sent = 0;
      int hits = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        hits++;
        final String? range = req.headers.value(HttpHeaders.rangeHeader);
        int start = 0;
        int end = all.length - 1;
        bool partial = false;
        if (honourRange && range != null && range.startsWith('bytes=')) {
          final List<String> parts = range.substring(6).split('-');
          start = int.parse(parts[0]);
          if (parts[1].isNotEmpty) end = int.parse(parts[1]);
          if (end >= all.length) end = all.length - 1;
          partial = true;
        }
        req.response.statusCode = partial
            ? HttpStatus.partialContent
            : HttpStatus.ok;
        if (partial) {
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${all.length}',
          );
        }
        final Uint8List slice = Uint8List.sublistView(all, start, end + 1);
        sent += slice.length;
        req.response.add(slice);
        await req.response.close();
      });
      return (server: server, bytesSent: () => sent, requests: hits);
    }

    test('remote extraction yields byte-identical output to local', () async {
      final dir = await Directory.systemTemp.createTemp('sft_range_');
      HttpServer? server;
      try {
        final source = await writeSafetensors(
          dir,
          'shard.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'noise': (dtype: 'F32', shape: <int>[64, 64]),
            'w': (dtype: 'F32', shape: <int>[8, 4]),
            'b': (dtype: 'F32', shape: <int>[8]),
          },
        );
        final served = await serveFile(source, honourRange: true);
        server = served.server;

        final local = File('${dir.path}/local.safetensors');
        await extractSafetensorsTensors(
          source: source,
          names: <String, String>{'w': 'w', 'b': 'b'},
          dest: local,
        );

        final remote = File('${dir.path}/remote.safetensors');
        await extractSafetensorsTensorsRemote(
          uri: Uri.parse('http://127.0.0.1:${served.server.port}/shard'),
          names: <String, String>{'w': 'w', 'b': 'b'},
          dest: remote,
          copyChunkBytes: 16,
        );

        expect(
          await sha256HexOfFile(remote),
          await sha256HexOfFile(local),
          reason: 'ranged path must reproduce the local extraction exactly',
        );

        // Header costs a few reads; the 160 bytes of payload must not drag
        // the whole 16 KB+ 'noise' tensor across the wire.
        expect(
          served.bytesSent(),
          lessThan(await source.length()),
          reason: 'ranged extraction must not transfer the full shard',
        );
      } finally {
        await server?.close(force: true);
        await dir.delete(recursive: true);
      }
    });

    test('readRemoteSafetensorsHeader matches the local header', () async {
      final dir = await Directory.systemTemp.createTemp('sft_rhdr_');
      HttpServer? server;
      try {
        final source = await writeSafetensors(
          dir,
          'shard.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'w': (dtype: 'F32', shape: <int>[8, 4]),
            'b': (dtype: 'F32', shape: <int>[8]),
          },
        );
        final served = await serveFile(source, honourRange: true);
        server = served.server;

        final local = await readSafetensorsHeader(source);
        final remote = await readRemoteSafetensorsHeader(
          uri: Uri.parse('http://127.0.0.1:${served.server.port}/shard'),
        );

        expect(remote.dataStart, local.dataStart);
        expect(remote.entries.keys.toSet(), local.entries.keys.toSet());
        for (final String key in local.entries.keys) {
          expect(remote.entries[key]!.shape, local.entries[key]!.shape);
          expect(remote.entries[key]!.start, local.entries[key]!.start);
          expect(remote.entries[key]!.end, local.entries[key]!.end);
          expect(remote.entries[key]!.dtype, local.entries[key]!.dtype);
        }
      } finally {
        await server?.close(force: true);
        await dir.delete(recursive: true);
      }
    });

    test('fails closed when the server ignores Range', () async {
      final dir = await Directory.systemTemp.createTemp('sft_norange_');
      HttpServer? server;
      try {
        final source = await writeSafetensors(
          dir,
          'shard.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'w': (dtype: 'F32', shape: <int>[8, 4]),
          },
        );
        final served = await serveFile(source, honourRange: false);
        server = served.server;

        await expectLater(
          readRemoteSafetensorsHeader(
            uri: Uri.parse('http://127.0.0.1:${served.server.port}/shard'),
          ),
          throwsA(isA<RangeNotSupportedException>()),
        );
      } finally {
        await server?.close(force: true);
        await dir.delete(recursive: true);
      }
    });

    test('reports progress that reaches the total', () async {
      final dir = await Directory.systemTemp.createTemp('sft_prog_');
      HttpServer? server;
      try {
        final source = await writeSafetensors(
          dir,
          'shard.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'w': (dtype: 'F32', shape: <int>[32, 16]),
            'b': (dtype: 'F32', shape: <int>[32]),
          },
        );
        final served = await serveFile(source, honourRange: true);
        server = served.server;

        int lastReceived = 0;
        int lastTotal = 0;
        await extractSafetensorsTensorsRemote(
          uri: Uri.parse('http://127.0.0.1:${served.server.port}/shard'),
          names: <String, String>{'w': 'w', 'b': 'b'},
          dest: File('${dir.path}/out.safetensors'),
          copyChunkBytes: 64,
          onProgress: (int r, int t) {
            lastReceived = r;
            lastTotal = t;
          },
        );

        expect(lastTotal, 32 * 16 * 4 + 32 * 4);
        expect(lastReceived, lastTotal);
      } finally {
        await server?.close(force: true);
        await dir.delete(recursive: true);
      }
    });

    test('missing tensor names fail before any bulk transfer', () async {
      final dir = await Directory.systemTemp.createTemp('sft_missing_');
      HttpServer? server;
      try {
        final source = await writeSafetensors(
          dir,
          'shard.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'w': (dtype: 'F32', shape: <int>[8, 4]),
          },
        );
        final served = await serveFile(source, honourRange: true);
        server = served.server;

        await expectLater(
          extractSafetensorsTensorsRemote(
            uri: Uri.parse('http://127.0.0.1:${served.server.port}/shard'),
            names: <String, String>{'nope': 'nope'},
            dest: File('${dir.path}/out.safetensors'),
          ),
          throwsStateError,
        );
      } finally {
        await server?.close(force: true);
        await dir.delete(recursive: true);
      }
    });
  });

  group('ZImageTensorExtraction header helpers', () {
    test('finds embed_tokens by shape in a parsed header', () async {
      final dir = await Directory.systemTemp.createTemp('zit_key_');
      try {
        final file = await writeSafetensors(
          dir,
          'enc.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'model.layers.0.mlp': (dtype: 'F32', shape: <int>[8, 8]),
            'model.embed_tokens.weight': (dtype: 'BF16', shape: <int>[4, 8]),
          },
        );
        final header = await readSafetensorsHeader(file);
        // Small stand-in shape: matching is magnitude-independent, and the
        // real [151936,2560] matrix would mean writing 778 MB per test.
        expect(
          ZImageTensorExtraction.findEmbedTokensKeyInHeader(
            header,
            expectedShape: <int>[4, 8],
          ),
          'model.embed_tokens.weight',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rejects ambiguous or absent embed_tokens', () async {
      final dir = await Directory.systemTemp.createTemp('zit_amb_');
      try {
        final none = await writeSafetensors(
          dir,
          'none.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'other.weight': (dtype: 'F32', shape: <int>[4, 4]),
          },
        );
        final noneHeader = await readSafetensorsHeader(none);
        expect(
          () => ZImageTensorExtraction.findEmbedTokensKeyInHeader(
            noneHeader,
            expectedShape: <int>[4, 8],
          ),
          throwsStateError,
        );

        // Two shape-matching candidates must be rejected, not guessed at.
        final two = await writeSafetensors(
          dir,
          'two.safetensors',
          <String, ({String dtype, List<int> shape})>{
            'a.embed_tokens.weight': (dtype: 'BF16', shape: <int>[4, 8]),
            'b.embed_tokens.weight': (dtype: 'BF16', shape: <int>[4, 8]),
          },
        );
        final twoHeader = await readSafetensorsHeader(two);
        expect(
          () => ZImageTensorExtraction.findEmbedTokensKeyInHeader(
            twoHeader,
            expectedShape: <int>[4, 8],
          ),
          throwsStateError,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}

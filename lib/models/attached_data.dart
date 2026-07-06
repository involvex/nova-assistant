import 'dart:io';

enum AttachedDataType { file, url, text }

class AttachedData {
  final String id;
  final String name;
  final AttachedDataType type;
  final String? filePath;
  final String? url;
  final String? extractedText;
  final DateTime attachedAt;
  final int? fileSizeBytes;

  const AttachedData({
    required this.id,
    required this.name,
    required this.type,
    this.filePath,
    this.url,
    this.extractedText,
    required this.attachedAt,
    this.fileSizeBytes,
  });

  double? get fileSizeMB =>
      fileSizeBytes != null ? fileSizeBytes! / (1024 * 1024) : null;

  bool get isExpired => type == AttachedDataType.url;

  String get displayName {
    switch (type) {
      case AttachedDataType.file:
        return name;
      case AttachedDataType.url:
        return url ?? name;
      case AttachedDataType.text:
        return name;
    }
  }

  AttachedData copyWith({
    String? name,
    String? extractedText,
    int? fileSizeBytes,
  }) {
    return AttachedData(
      id: id,
      name: name ?? this.name,
      type: type,
      filePath: filePath,
      url: url,
      extractedText: extractedText ?? this.extractedText,
      attachedAt: attachedAt,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'filePath': filePath,
    'url': url,
    'extractedText': extractedText,
    'attachedAt': attachedAt.toIso8601String(),
    'fileSizeBytes': fileSizeBytes,
  };

  factory AttachedData.fromJson(Map<String, dynamic> json) => AttachedData(
    id: json['id'] as String,
    name: json['name'] as String,
    type: AttachedDataType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => AttachedDataType.text,
    ),
    filePath: json['filePath'] as String?,
    url: json['url'] as String?,
    extractedText: json['extractedText'] as String?,
    attachedAt: DateTime.parse(json['attachedAt'] as String),
    fileSizeBytes: json['fileSizeBytes'] as int?,
  );

  /// Build a context string to inject into the system prompt or user query.
  Future<String> buildContextString() async {
    switch (type) {
      case AttachedDataType.file:
        return _buildFileContext();
      case AttachedDataType.url:
        return _buildUrlContext();
      case AttachedDataType.text:
        return '[Attached text: $name]\n${extractedText ?? ""}';
    }
  }

  Future<String> _buildFileContext() async {
    if (filePath == null) return '[File: $name (path unknown)]';

    final file = File(filePath!);
    if (!await file.exists()) return '[File: $name (not found)]';

    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt':
      case 'md':
      case 'json':
      case 'csv':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'log':
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'java':
      case 'kt':
      case 'swift':
      case 'c':
      case 'cpp':
      case 'h':
      case 'html':
      case 'css':
      case 'sql':
      case 'sh':
      case 'bat':
      case 'ps1':
        final content = await file.readAsString();
        final preview = content.length > 5000
            ? '${content.substring(0, 5000)}\n\n... (truncated, ${content.length} chars total)'
            : content;
        return '[File: $name]\n```\n$preview\n```';
      case 'pdf':
        return '[File: $name (PDF - ${fileSizeMB?.toStringAsFixed(1) ?? "?"}MB)]';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return '[Image: $name]';
      default:
        return '[File: $name ($ext)]';
    }
  }

  Future<String> _buildUrlContext() async {
    final buffer = StringBuffer();
    buffer.writeln('[URL: ${url ?? name}]');
    if (extractedText != null && extractedText!.isNotEmpty) {
      final preview = extractedText!.length > 3000
          ? '${extractedText!.substring(0, 3000)}\n\n... (truncated)'
          : extractedText!;
      buffer.writeln(preview);
    }
    return buffer.toString();
  }
}

class AttachmentManager {
  static AttachmentManager? _instance;
  static AttachmentManager get instance => _instance ??= AttachmentManager._();
  AttachmentManager._();

  final List<AttachedData> _attachments = [];

  List<AttachedData> get attachments => List.unmodifiable(_attachments);

  bool get hasAttachments => _attachments.isNotEmpty;

  int get count => _attachments.length;

  void add(AttachedData attachment) {
    _attachments.add(attachment);
  }

  void remove(String id) {
    _attachments.removeWhere((a) => a.id == id);
  }

  void clear() {
    _attachments.clear();
  }

  /// Build a combined context string from all attachments.
  Future<String> buildAllContext() async {
    if (_attachments.isEmpty) return '';

    final buffers = <String>[];
    for (final attachment in _attachments) {
      final context = await attachment.buildContextString();
      buffers.add(context);
    }
    return buffers.join('\n\n');
  }
}

import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocumentExtractor {
  /// Supported text-based extensions that can be read directly.
  static const _textExtensions = {
    'txt',
    'md',
    'json',
    'csv',
    'xml',
    'yaml',
    'yml',
    'log',
    'dart',
    'js',
    'ts',
    'py',
    'java',
    'kt',
    'swift',
    'c',
    'cpp',
    'h',
    'html',
    'css',
    'sql',
    'sh',
    'bat',
    'ps1',
    'toml',
    'ini',
    'cfg',
    'conf',
    'env',
    'gitignore',
    'dockerfile',
  };

  /// Supported image extensions (delegated to vision model).
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  /// Returns true if the file extension is a recognized image type.
  static bool isImageFile(String fileName) {
    final ext = _extension(fileName);

    return _imageExtensions.contains(ext);
  }

  /// Returns true if the file extension is a supported text type.
  static bool isTextFile(String fileName) {
    final ext = _extension(fileName);

    return _textExtensions.contains(ext);
  }

  /// Returns true if the file extension is a PDF.
  static bool isPdfFile(String fileName) {
    return _extension(fileName) == 'pdf';
  }

  /// Extract text content from a file at [filePath].
  static Future<String> extractText(String filePath, String fileName) async {
    final ext = _extension(fileName);
    final file = File(filePath);

    if (!await file.exists()) {
      return '[File not found: $fileName]';
    }

    if (_textExtensions.contains(ext)) {
      return _extractTextFile(filePath);
    }

    if (ext == 'pdf') {
      return _extractPdf(filePath, fileName);
    }

    if (_imageExtensions.contains(ext)) {
      return '[Image: $fileName — use vision model to analyze]';
    }

    return '[File: $fileName (.$ext) — unsupported format for text extraction]';
  }

  static Future<String> _extractTextFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();

      if (content.length > 10000) {
        return '${content.substring(0, 10000)}\n\n'
            '... (truncated, ${content.length} chars total)';
      }

      return content;
    } catch (e) {
      return '[Error reading file: $e]';
    }
  }

  /// Extract text from a PDF using Syncfusion PDF.
  static Future<String> _extractPdf(String filePath, String fileName) async {
    PdfDocument? document;
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      document = PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      if (pageCount == 0) {
        return '[PDF: $fileName — no pages found]';
      }

      final extractor = PdfTextExtractor(document);
      final buffer = StringBuffer();
      for (var i = 0; i < pageCount; i++) {
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        if (pageText.trim().isEmpty) continue;
        if (buffer.isNotEmpty) {
          buffer.writeln('\n--- Page ${i + 1} ---\n');
        }
        buffer.writeln(pageText.trim());
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) {
        final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);

        return '[PDF: $fileName ($sizeMB MB, $pageCount pages) — '
            'no extractable text (may be scanned/image-only)]';
      }

      if (text.length > 100000) {
        return '${text.substring(0, 100000)}\n\n'
            '... (truncated, ${text.length} chars from $pageCount pages)';
      }

      return text;
    } catch (e) {
      return '[Error reading PDF: $e]';
    } finally {
      document?.dispose();
    }
  }

  static String _extension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';

    return fileName.substring(lastDot + 1).toLowerCase();
  }
}

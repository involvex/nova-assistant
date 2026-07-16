import 'dart:io';

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
  ///
  /// For text files, reads the content directly.
  /// For PDFs, returns a structured placeholder with metadata.
  /// For images, returns a placeholder (should be handled by vision model).
  /// For unknown types, returns a placeholder.
  static Future<String> extractText(String filePath, String fileName) async {
    final ext = _extension(fileName);
    final file = File(filePath);

    if (!await file.exists()) {
      return '[File not found: $fileName]';
    }

    // Text files — read directly
    if (_textExtensions.contains(ext)) {
      return _extractTextFile(filePath);
    }

    // PDF — extract text or return metadata
    if (ext == 'pdf') {
      return _extractPdf(filePath, fileName);
    }

    // Images — delegate to vision model
    if (_imageExtensions.contains(ext)) {
      return '[Image: $fileName — use vision model to analyze]';
    }

    // Unknown type
    return '[File: $fileName (.$ext) — unsupported format for text extraction]';
  }

  /// Extract text from a plain text file with size guard.
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

  /// Extract text from a PDF file.
  ///
  /// Currently returns a metadata placeholder. To add real PDF extraction,
  /// add `syncfusion_flutter_pdf` to pubspec.yaml and uncomment the
  /// extraction code below.
  static Future<String> _extractPdf(String filePath, String fileName) async {
    try {
      final file = File(filePath);
      final sizeBytes = await file.length();
      final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

      // TODO: Add syncfusion_flutter_pdf for real extraction:
      //
      // import 'package:syncfusion_flutter_pdf/pdf.dart';
      // final bytes = await file.readAsBytes();
      // final document = PdfDocument(inputBytes: bytes);
      // final buffer = StringBuffer();
      // for (int i = 0; i < document.pages.count; i++) {
      //   buffer.writeln(document.pages[i].extractText());
      //   buffer.writeln('\n--- Page ${i + 1} ---\n');
      // }
      // document.dispose();
      // return buffer.toString();

      return '[PDF: $fileName ($sizeMB MB, ${_formatPageCount(sizeBytes)} '
          'approx pages) — text extraction pending implementation]';
    } catch (e) {
      return '[Error reading PDF: $e]';
    }
  }

  /// Rough page count estimate based on file size (for placeholder display).
  static String _formatPageCount(int sizeBytes) {
    final pages = (sizeBytes / 50000).round();
    return '~$pages';
  }

  /// Extract the file extension (lowercase, without the dot).
  static String _extension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }
}

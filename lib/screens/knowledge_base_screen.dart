import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:nova_assistant/services/knowledge_base_service.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final _service = KnowledgeBaseService.instance;
  List<KnowledgeDocument> _documents = [];
  bool _loading = true;
  bool _enabled = true;
  bool _ingesting = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final docs = await _service.listDocuments();
    final enabled = await _service.isEnabled();
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _pickAndIngest() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'txt',
        'md',
        'pdf',
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
        'html',
        'css',
        'sql',
      ],
          );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final path = file.path;
    if (path == null) {
      _snack('Could not read file path');

      return;
    }

    setState(() => _ingesting = true);
    final doc = await _service.ingestFile(filePath: path, fileName: file.name);
    if (!mounted) return;
    setState(() => _ingesting = false);

    if (doc == null) {
      _snack('Failed to extract text from ${file.name}');

      return;
    }
    _snack('Added ${doc.name} (${doc.chunks.length} chunks)');
    await _load();
  }

  Future<void> _delete(KnowledgeDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Delete document?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove "${doc.name}" from the knowledge base?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteDocument(doc.id);
    await _load();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  List<KnowledgeDocument> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _documents;

    return _documents
        .where(
          (d) =>
              d.name.toLowerCase().contains(q) ||
              d.fullText.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          if (_ingesting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _pickAndIngest,
              icon: const Icon(Icons.add),
              tooltip: 'Add document',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Use in chat context',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Inject relevant chunks into RAG prompts',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  value: _enabled,
                  activeThumbColor: const Color(0xFF6C63FF),
                  onChanged: (v) async {
                    await _service.setEnabled(v);
                    setState(() => _enabled = v);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search documents…',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _documents.isEmpty
                                ? 'No documents yet.\nTap + to add PDF or text files.'
                                : 'No matches.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final doc = _filtered[index];

                            return Card(
                              color: const Color(0xFF1A1A2E),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  doc.name.toLowerCase().endsWith('.pdf')
                                      ? Icons.picture_as_pdf
                                      : Icons.description_outlined,
                                  color: const Color(0xFF6C63FF),
                                ),
                                title: Text(
                                  doc.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${doc.chunks.length} chunks · '
                                  '${doc.charCount} chars',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _delete(doc),
                                ),
                                onTap: () => _showPreview(doc),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _ingesting ? null : _pickAndIngest,
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.upload_file),
      ),
    );
  }

  void _showPreview(KnowledgeDocument doc) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Text(
                doc.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                doc.fullText.length > 4000
                    ? '${doc.fullText.substring(0, 4000)}…'
                    : doc.fullText,
                style: TextStyle(color: Colors.grey[300], height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


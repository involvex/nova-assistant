import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/models/inference_backend.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/remote_inference_client.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';

/// Configure OpenAI-compatible LAN remote inference (llama-server / Ollama).
class RemoteInferenceSettingsScreen extends StatefulWidget {
  const RemoteInferenceSettingsScreen({super.key});

  @override
  State<RemoteInferenceSettingsScreen> createState() =>
      _RemoteInferenceSettingsScreenState();
}

class _RemoteInferenceSettingsScreenState
    extends State<RemoteInferenceSettingsScreen> {
  InferenceBackend _backend = InferenceBackend.onDevice;
  final _baseUrlController = TextEditingController();
  final _modelIdController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final config = RemoteInferenceConfig.fromPrefs(prefs);
    if (!mounted) return;
    setState(() {
      _backend = RemoteInferenceConfig.backendFromPrefs(prefs);
      _baseUrlController.text = config.baseUrl;
      _modelIdController.text = config.modelId;
      _tokenController.text = config.apiToken ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final config = RemoteInferenceConfig(
      baseUrl: _baseUrlController.text.trim(),
      modelId: _modelIdController.text.trim(),
      apiToken: _tokenController.text.trim().isEmpty
          ? null
          : _tokenController.text.trim(),
    );
    await config.save(prefs);
    await RemoteInferenceConfig.saveBackend(prefs, _backend);
    await ModelOrchestrator.refreshSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remote inference settings saved')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final config = RemoteInferenceConfig(
      baseUrl: _baseUrlController.text.trim(),
      modelId: _modelIdController.text.trim(),
      apiToken: _tokenController.text.trim().isEmpty
          ? null
          : _tokenController.text.trim(),
    );
    final client = RemoteInferenceClient();
    final ok = await client.testConnection(config);
    client.close();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok
          ? 'Connected — /v1/models responded OK'
          : 'Connection failed — check URL, Wi‑Fi, and host firewall';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Remote LAN inference'),
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'Only use on trusted private Wi‑Fi. Do not expose your '
                    'model host to the public internet without a firewall and token.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Backend',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<InferenceBackend>(
                  segments: const [
                    ButtonSegment(
                      value: InferenceBackend.onDevice,
                      label: Text('On-device'),
                      icon: Icon(Icons.phone_android),
                    ),
                    ButtonSegment(
                      value: InferenceBackend.remote,
                      label: Text('Remote LAN'),
                      icon: Icon(Icons.lan_outlined),
                    ),
                  ],
                  selected: {_backend},
                  onSelectionChanged: (s) {
                    setState(() => _backend = s.first);
                  },
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _baseUrlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'http://192.168.x.x:8080',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF6C63FF)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modelIdController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Model id',
                    hintText: 'local-model',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF6C63FF)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'API token (optional)',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF6C63FF)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testResult!.startsWith('Connected')
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Host with llama-server:\n'
                  'llama-server -m model.gguf --host 0.0.0.0 --port 8080\n\n'
                  'Point Nova at http://<pc-lan-ip>:8080 — this is how large '
                  'GGUF models work today without on-device GGUF.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
    );
  }
}

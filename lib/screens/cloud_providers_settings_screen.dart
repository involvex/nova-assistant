import 'package:flutter/material.dart';

import 'package:nova_assistant/ai/bootstrap.dart';
import 'package:nova_assistant/ai/router/routing_preset.dart';
import 'package:nova_assistant/core/config/cloud_provider_config.dart';

/// Configure cloud provider credentials (OpenAI-compatible `/v1`).
///
/// Base URL + model id persist in SharedPreferences (included in settings
/// backups); API tokens persist in secure storage and are never backed up.
class CloudProvidersSettingsScreen extends StatefulWidget {
  const CloudProvidersSettingsScreen({super.key});

  @override
  State<CloudProvidersSettingsScreen> createState() =>
      _CloudProvidersSettingsScreenState();
}

class _ProviderControllers {
  _ProviderControllers()
    : baseUrl = TextEditingController(),
      modelId = TextEditingController(),
      token = TextEditingController();

  final TextEditingController baseUrl;
  final TextEditingController modelId;
  final TextEditingController token;
  bool testing = false;
  String? testResult;
  bool tokenSaved = true;
  bool fetchingModels = false;
  String? modelsError;

  void dispose() {
    baseUrl.dispose();
    modelId.dispose();
    token.dispose();
  }
}

class _CloudProvidersSettingsScreenState
    extends State<CloudProvidersSettingsScreen> {
  final Map<String, _ProviderControllers> _controllers =
      <String, _ProviderControllers>{};
  bool _loading = true;
  RoutingPreset _preset = RoutingPreset.free;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final _ProviderControllers controllers in _controllers.values) {
      controllers.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    const CloudProviderStore store = CloudProviderStore();
    final RoutingPreset preset = await RoutingPresetStore.load();
    for (final CloudProviderEntry entry in kCloudProviders) {
      final CloudProviderValues values = await store.load(entry);
      final _ProviderControllers controllers = _controllers[entry.id] ??=
          _ProviderControllers();
      controllers.baseUrl.text = values.baseUrl;
      controllers.modelId.text = values.modelId;
      controllers.token.text = values.apiToken ?? '';
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _preset = preset;
      _loading = false;
    });
  }

  Future<void> _save(CloudProviderEntry entry) async {
    final _ProviderControllers? controllers = _controllers[entry.id];
    if (controllers == null) {
      return;
    }
    final String baseUrl = controllers.baseUrl.text.trim().isEmpty
        ? entry.defaultBaseUrl
        : controllers.baseUrl.text.trim();
    final String modelId = controllers.modelId.text.trim().isEmpty
        ? entry.defaultModelId
        : controllers.modelId.text.trim();
    try {
      final bool tokenSaved = await const CloudProviderStore().save(
        entry,
        baseUrl: baseUrl,
        modelId: modelId,
        apiToken: controllers.token.text,
      );
      // Push fresh URL/model/token into the registry + availability cache so
      // smart routing picks the provider up without an app restart.
      await NovaBootstrap.refreshProviderConfigs();
      if (!mounted) {
        return;
      }
      setState(() => controllers.tokenSaved = tokenSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tokenSaved
                ? '${entry.displayName} saved'
                : '${entry.displayName} saved, but token storage failed — '
                      're-enter the token later',
          ),
        ),
      );
    } on ArgumentError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${entry.displayName}: ${e.message}'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  Future<void> _test(CloudProviderEntry entry) async {
    final _ProviderControllers? controllers = _controllers[entry.id];
    if (controllers == null) {
      return;
    }
    setState(() {
      controllers.testing = true;
      controllers.testResult = null;
    });
    try {
      // Persist first so the test reflects what will actually be used.
      await _saveWithoutSnack(entry, controllers);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        controllers.testing = false;
        controllers.testResult = '${e.message}';
      });
      return;
    }
    final CloudProviderValues values = await const CloudProviderStore().load(
      entry,
    );
    final bool ok = await const CloudProviderStore().testConnection(values);
    if (!mounted) {
      return;
    }
    setState(() {
      controllers.testing = false;
      controllers.testResult = ok
          ? 'Connected — /v1/models responded OK'
          : 'Connection failed — check URL, token, and network';
    });
  }

  Future<void> _fetchModels(CloudProviderEntry entry) async {
    final _ProviderControllers? controllers = _controllers[entry.id];
    if (controllers == null || controllers.fetchingModels) {
      return;
    }
    setState(() {
      controllers.fetchingModels = true;
      controllers.modelsError = null;
    });
    // Persist first so the fetch uses the currently entered URL/token.
    List<String> ids;
    try {
      await _saveWithoutSnack(entry, controllers);
      final CloudProviderValues values = await const CloudProviderStore().load(
        entry,
      );
      ids = await const CloudProviderStore().fetchModels(values);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        controllers.fetchingModels = false;
        controllers.modelsError = '$e'.replaceFirst('Exception: ', '');
      });

      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => controllers.fetchingModels = false);
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('${entry.displayName} models (${ids.length})'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ids.length,
              itemBuilder: (BuildContext _, int index) {
                final String id = ids[index];
                final bool selected = id == controllers.modelId.text.trim();

                return ListTile(
                  dense: true,
                  title: Text(id, style: const TextStyle(fontSize: 13)),
                  trailing: selected ? const Icon(Icons.check, size: 18) : null,
                  onTap: () => Navigator.of(dialogContext).pop(id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => controllers.modelId.text = picked);
      await _save(entry);
    }
  }

  Future<void> _saveWithoutSnack(
    CloudProviderEntry entry,
    _ProviderControllers controllers,
  ) async {
    final String baseUrl = controllers.baseUrl.text.trim().isEmpty
        ? entry.defaultBaseUrl
        : controllers.baseUrl.text.trim();
    final String modelId = controllers.modelId.text.trim().isEmpty
        ? entry.defaultModelId
        : controllers.modelId.text.trim();
    final bool tokenSaved = await const CloudProviderStore().save(
      entry,
      baseUrl: baseUrl,
      modelId: modelId,
      apiToken: controllers.token.text,
    );
    controllers.tokenSaved = tokenSaved;
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white54),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF6C63FF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Cloud providers'),
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
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
                    'API tokens are stored only in secure device storage and '
                    'are never included in settings backups. Traffic goes '
                    'directly to the configured provider. Pin a provider as '
                    'your chat model via the model selector (Manual → Cloud), '
                    'or enable Smart routing so Nova picks per task.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                _presetCard(),
                const SizedBox(height: 12),
                for (final CloudProviderEntry entry in kCloudProviders)
                  _providerCard(entry),
              ],
            ),
    );
  }

  /// Smart-routing setup: which (provider, model) chain auto-routed cloud
  /// turns try. Free never spends money unasked.
  Widget _presetCard() {
    final List<CloudTarget> chain = presetTargets(_preset);
    final CloudTarget first = chain.first;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart routing setup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<RoutingPreset>(
            segments: const <ButtonSegment<RoutingPreset>>[
              ButtonSegment(
                value: RoutingPreset.free,
                icon: Icon(Icons.money_off_outlined, size: 16),
                label: Text('Free'),
              ),
              ButtonSegment(
                value: RoutingPreset.balanced,
                icon: Icon(Icons.balance_outlined, size: 16),
                label: Text('Balanced'),
              ),
              ButtonSegment(
                value: RoutingPreset.max,
                icon: Icon(Icons.rocket_launch_outlined, size: 16),
                label: Text('Max'),
              ),
            ],
            selected: <RoutingPreset>{_preset},
            onSelectionChanged: (Set<RoutingPreset> selected) async {
              final RoutingPreset next = selected.first;
              await RoutingPresetStore.save(next);
              if (mounted) {
                setState(() => _preset = next);
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Auto cloud turns try ${first.providerId} · ${first.modelId ?? 'provider default'} first.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _providerCard(CloudProviderEntry entry) {
    final _ProviderControllers controllers = _controllers[entry.id] ??=
        _ProviderControllers();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: ExpansionTile(
          leading: const Icon(Icons.cloud_outlined, color: Color(0xFF6C63FF)),
          title: Text(
            entry.displayName,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          subtitle: Text(
            entry.help,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: controllers.baseUrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: _decoration('Base URL', hint: entry.defaultBaseUrl),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controllers.modelId,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Model id', hint: entry.defaultModelId)
                  .copyWith(
                    suffixIcon: controllers.fetchingModels
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Fetch model list',
                            icon: const Icon(Icons.cloud_download_outlined),
                            onPressed: () => _fetchModels(entry),
                          ),
                  ),
            ),
            if (controllers.modelsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  controllers.modelsError!,
                  style: TextStyle(fontSize: 12, color: Colors.red[300]),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controllers.token,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('API token'),
            ),
            if (!controllers.tokenSaved)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Token could not be stored securely on this device.',
                  style: TextStyle(fontSize: 12, color: Colors.red[300]),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controllers.testing ? null : () => _test(entry),
                    icon: controllers.testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(controllers.testing ? 'Testing…' : 'Test'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _save(entry),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
            if (controllers.testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                controllers.testResult!,
                style: TextStyle(
                  fontSize: 12,
                  color: controllers.testResult!.startsWith('Connected')
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NovaChannels {
  NovaChannels._();

  static const assistantTools = 'dev.nova.assistant/tools';
  static const modelService = 'dev.nova.assistant/model_service';
  static const imageGen = 'dev.nova.assistant/image_gen';
  static const diagnostics = 'dev.nova.assistant/diagnostics';
  static const screenshot = 'dev.nova.assistant/screenshot';
  static const platform = 'dev.nova.assistant/platform';
}

class NovaPrefsKeys {
  NovaPrefsKeys._();

  static const installedModels = 'installed_models';
  static const customModels = 'custom_models';
  static const hfToken = 'hf_token';
  static const diffusionModels = 'diffusion_models';
  static const settingsKeepModelWarm = 'settings_keep_model_warm';
  static const settingsHighContext = 'settings_high_context';
  static const settingsRemoteBaseUrl = 'settings_remote_base_url';
  static const settingsRemoteModelId = 'settings_remote_model_id';
  static const settingsRemoteApiToken = 'settings_remote_api_token';
  static const settingsInferenceBackend = 'settings_inference_backend';
  static const mcpServers = 'mcp_servers';
  static const mcpSources = 'mcp_sources';
  static const mcpTools = 'mcp_tools';
}

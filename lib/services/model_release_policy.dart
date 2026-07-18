class ModelReleasePolicy {
  static bool shouldReleaseOnPause({
    required bool keepModelWarm,
    required bool isStreaming,
  }) {
    if (isStreaming) return false;
    if (keepModelWarm) return false;

    return true;
  }

  static bool shouldReleaseOnIdle({
    required bool batteryOptimizationEnabled,
    required bool isStreaming,
    required bool isLoadingModel,
  }) {
    if (!batteryOptimizationEnabled) return false;
    if (isStreaming || isLoadingModel) return false;

    return true;
  }
}

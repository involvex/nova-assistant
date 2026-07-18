/// Where Nova runs chat completions.
enum InferenceBackend {
  onDevice,
  remote;

  static InferenceBackend fromPrefsValue(String? value) {
    switch (value) {
      case 'remote':
        return InferenceBackend.remote;
      case 'onDevice':
      default:
        return InferenceBackend.onDevice;
    }
  }

  String get prefsValue => name;
}

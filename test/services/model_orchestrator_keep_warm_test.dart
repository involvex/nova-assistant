import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/model_release_policy.dart';

void main() {
  test('keep warm blocks pause release', () {
    expect(
      ModelReleasePolicy.shouldReleaseOnPause(
        keepModelWarm: true,
        isStreaming: false,
      ),
      isFalse,
    );
  });

  test('streaming always blocks pause release', () {
    expect(
      ModelReleasePolicy.shouldReleaseOnPause(
        keepModelWarm: false,
        isStreaming: true,
      ),
      isFalse,
    );
  });

  test('idle release respects battery flag', () {
    expect(
      ModelReleasePolicy.shouldReleaseOnIdle(
        batteryOptimizationEnabled: false,
        isStreaming: false,
        isLoadingModel: false,
      ),
      isFalse,
    );
  });
}

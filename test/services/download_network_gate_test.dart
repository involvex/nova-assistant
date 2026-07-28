import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/download_network_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DownloadNetworkGate.reset();
  });

  tearDown(DownloadNetworkGate.reset);

  test('wifi-only preference defaults to false and persists', () async {
    expect(await DownloadNetworkGate.instance.isWifiOnlyEnabled(), isFalse);
    await DownloadNetworkGate.instance.setWifiOnlyEnabled(true);
    expect(await DownloadNetworkGate.instance.isWifiOnlyEnabled(), isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/screens/cloud_providers_settings_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders all four cloud providers', (WidgetTester tester) async {
    // Tall surface: the preset card plus all provider cards must be laid
    // out (ListView builds lazily, offscreen cards would not exist).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: CloudProvidersSettingsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Groq'), findsOneWidget);
    expect(find.text('Opencode Zen'), findsOneWidget);
    expect(find.text('Kilo Gateway'), findsOneWidget);
    expect(find.text('Smart routing setup'), findsOneWidget);

    // Expand the first provider card and verify credential fields appear.
    await tester.tap(find.text('OpenRouter'));
    await tester.pumpAndSettle();

    expect(find.text('Base URL'), findsOneWidget);
    expect(find.text('Model id'), findsOneWidget);
    expect(find.text('API token'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/widgets/image_generation_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.nova.assistant/image_gen');
  const blockedPrompt = 'a nude portrait';
  const safePrompt = 'a cat on a skateboard';

  bool modelInstalled = true;
  int generateCalls = 0;
  Object? lastGenerateArgs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    modelInstalled = true;
    generateCalls = 0;
    lastGenerateArgs = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isModelInstalled':
              return modelInstalled;
            case 'generateImage':
              generateCalls++;
              lastGenerateArgs = call.arguments;
              return Uint8List.fromList([9, 8, 7]);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<_SheetResultHolder> pumpAndOpenSheet(WidgetTester tester) async {
    final holder = _SheetResultHolder();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  holder.result = await showImageGenerationSheet(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return holder;
  }

  testWidgets('renders prompt field and size chips', (tester) async {
    await pumpAndOpenSheet(tester);

    expect(find.text('Describe the image to generate...'), findsOneWidget);
    expect(find.text('256x256'), findsOneWidget);
    expect(find.text('512x512'), findsOneWidget);
    expect(find.text('1024x1024'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('shows guidance when no diffusion model is installed', (
    tester,
  ) async {
    modelInstalled = false;
    await pumpAndOpenSheet(tester);

    expect(find.text('No diffusion model'), findsOneWidget);
    expect(find.text('Open Settings to install'), findsOneWidget);
  });

  testWidgets('blocked prompt surfaces policy message without generation', (
    tester,
  ) async {
    await pumpAndOpenSheet(tester);

    await tester.enterText(find.byType(TextField), blockedPrompt);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Blocked by the safety filter'), findsOneWidget);
    expect(generateCalls, 0);
  });

  testWidgets('rapid double-tap on Generate triggers a single generation', (
    tester,
  ) async {
    await pumpAndOpenSheet(tester);

    await tester.enterText(find.byType(TextField), safePrompt);
    final button = find.byType(FilledButton);
    await tester.tap(button, warnIfMissed: false);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(generateCalls, 1);
    expect(find.textContaining('Generation failed'), findsNothing);
  });

  testWidgets('busy state resets after blocked prompt so retry works', (
    tester,
  ) async {
    final holder = await pumpAndOpenSheet(tester);

    await tester.enterText(find.byType(TextField), blockedPrompt);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(generateCalls, 0);

    await tester.enterText(find.byType(TextField), safePrompt);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(holder.result, isNotNull);
    expect(generateCalls, 1);
  });

  testWidgets('successful generation pops with prompt and bytes', (
    tester,
  ) async {
    final holder = await pumpAndOpenSheet(tester);

    await tester.enterText(find.byType(TextField), safePrompt);
    await tester.tap(find.text('256x256'));
    await tester.pump();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(holder.result, isNotNull);
    expect(holder.result!.prompt, safePrompt);
    expect(holder.result!.bytes, isNotEmpty);
    expect(find.byType(ImageGenerationSheet), findsNothing);
    expect(generateCalls, 1);
    expect((lastGenerateArgs as Map<Object?, Object?>)['size'], 256);
  });

  testWidgets('generation failure keeps sheet open with error message', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isModelInstalled':
              return true;
            case 'generateImage':
              generateCalls++;
              return null;
          }
          return null;
        });

    await pumpAndOpenSheet(tester);

    await tester.enterText(find.byType(TextField), safePrompt);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(find.byType(ImageGenerationSheet), findsOneWidget);
    expect(find.textContaining('Generation failed'), findsOneWidget);
  });
}

class _SheetResultHolder {
  ImageGenerationResult? result;
}

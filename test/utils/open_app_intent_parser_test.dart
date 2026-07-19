import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/open_app_intent_parser.dart';

void main() {
  group('OpenAppIntentParser', () {
    test('parses English open YouTube', () {
      expect(
        OpenAppIntentParser.tryParsePackage('open youtube'),
        'com.google.android.youtube',
      );
    });

    test('parses German öffne YouTube', () {
      expect(
        OpenAppIntentParser.tryParsePackage('öffne Youtube'),
        'com.google.android.youtube',
      );
    });

    test('parses aufmachen as open intent', () {
      expect(
        OpenAppIntentParser.tryParsePackage(
          'kannst du mir Youtube aufmachen mit Elektrik Callboy',
        ),
        'com.google.android.youtube',
      );
      expect(
        OpenAppIntentParser.tryParsePackage('mach youtube auf'),
        'com.google.android.youtube',
      );
    });

    test('parses settings', () {
      expect(
        OpenAppIntentParser.tryParsePackage('open settings'),
        'com.android.settings',
      );
      expect(
        OpenAppIntentParser.tryParsePackage('öffne Einstellungen'),
        'com.android.settings',
      );
    });

    test('returns null without open intent', () {
      expect(OpenAppIntentParser.tryParsePackage('what is youtube'), isNull);
    });

    test('does not match geöffnet as open intent', () {
      expect(
        OpenAppIntentParser.tryParsePackage('Ist YouTube schon geöffnet?'),
        isNull,
      );
    });

    test('parses German öffnen infinitive', () {
      expect(
        OpenAppIntentParser.tryParsePackage('kannst du YouTube öffnen'),
        'com.google.android.youtube',
      );
    });

    test('prefers explicit package id over youtube substring', () {
      expect(
        OpenAppIntentParser.tryParsePackage(
          'open app.revanced.android.youtube',
        ),
        'app.revanced.android.youtube',
      );
      expect(
        OpenAppIntentParser.tryParsePackage('öffne app.morphe.android.youtube'),
        'app.morphe.android.youtube',
      );
    });

    test('parses revanced / morphe aliases', () {
      expect(
        OpenAppIntentParser.tryParsePackage('open revanced'),
        'app.revanced.android.youtube',
      );
      expect(
        OpenAppIntentParser.tryParsePackage('open yt revanced'),
        'app.revanced.android.youtube',
      );
      expect(
        OpenAppIntentParser.tryParsePackage('open morphe'),
        'app.morphe.android.youtube',
      );
    });
  });
}

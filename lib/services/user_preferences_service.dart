import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/models/user_preferences.dart';

class UserPreferencesService {
  static const String _key = 'user_preferences';

  static UserPreferencesService? _instance;
  static UserPreferencesService get instance =>
      _instance ??= UserPreferencesService._();

  UserPreferencesService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<UserPreferences> getPreferences() async {
    final prefs = await _p;
    final json = prefs.getString(_key);
    if (json == null) return const UserPreferences();
    try {
      return UserPreferences.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return const UserPreferences();
    }
  }

  Future<void> savePreferences(UserPreferences prefs) async {
    final p = await _p;
    await p.setString(_key, jsonEncode(prefs.toJson()));
  }

  Future<UserMode> getMode() async {
    final prefs = await getPreferences();
    return prefs.mode;
  }

  Future<void> setMode(UserMode mode) async {
    final current = await getPreferences();
    await savePreferences(current.copyWith(mode: mode));
  }

  Future<String> getUserName() async {
    final prefs = await getPreferences();
    return prefs.userName;
  }

  Future<void> setUserName(String name) async {
    final current = await getPreferences();
    await savePreferences(current.copyWith(userName: name));
  }

  Future<bool> isOnboardingComplete() async {
    final prefs = await getPreferences();
    return prefs.onboardingComplete;
  }

  Future<void> setOnboardingComplete(bool complete) async {
    final current = await getPreferences();
    await savePreferences(current.copyWith(onboardingComplete: complete));
  }

  Future<bool> hasSeenBeginnerSimplifiedPrompt() async {
    final prefs = await getPreferences();
    return prefs.beginnerHasSeenSimplifiedPrompt;
  }

  Future<void> setBeginnerSimplifiedPromptSeen(bool seen) async {
    final current = await getPreferences();
    await savePreferences(
      current.copyWith(beginnerHasSeenSimplifiedPrompt: seen),
    );
  }

  Future<bool> isFirstLaunch() async {
    final prefs = await getPreferences();
    return !prefs.onboardingComplete;
  }

  Future<void> clear() async {
    final p = await _p;
    await p.remove(_key);
  }

  Future<void> resetToDefaults() async {
    await savePreferences(const UserPreferences());
  }
}

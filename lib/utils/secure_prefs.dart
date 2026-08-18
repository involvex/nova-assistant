import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurePrefs {
  static final SecurePrefs _instance = SecurePrefs._();
  factory SecurePrefs() => _instance;
  SecurePrefs._();

  static const _secure = FlutterSecureStorage();

  Future<String?> read(String key) async {
    try {
      final value = await _secure.read(key: key);
      if (value != null) return value;
    } catch (e) {
      debugPrint('SecurePrefs: failed to read $key from secure storage: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy != null) {
      await write(key, legacy);
      await prefs.remove(key);
    }
    return legacy;
  }

  Future<void> write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecurePrefs: failed to write $key to secure storage: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  Future<void> delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (e) {
      debugPrint('SecurePrefs: failed to delete $key from secure storage: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<bool> containsKey(String key) async {
    try {
      final value = await _secure.read(key: key);
      if (value != null) return true;
    } catch (e) {
      debugPrint('SecurePrefs: failed to check $key in secure storage: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key);
  }
}

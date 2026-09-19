import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemePreferenceStore {
  Future<ThemeMode> load();

  Future<void> save(ThemeMode mode);
}

class ThemePreferenceSaveException implements Exception {
  const ThemePreferenceSaveException();
}

class SharedPreferencesThemePreferenceStore implements ThemePreferenceStore {
  static const _key = 'appearance.theme_mode';

  @override
  Future<ThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> save(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, mode.name)) {
      throw const ThemePreferenceSaveException();
    }
  }
}

class InMemoryThemePreferenceStore implements ThemePreferenceStore {
  InMemoryThemePreferenceStore([this.value = ThemeMode.system]);

  ThemeMode value;

  @override
  Future<ThemeMode> load() async => value;

  @override
  Future<void> save(ThemeMode mode) async {
    value = mode;
  }
}

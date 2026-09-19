import 'package:flutter/material.dart';

import '../data/theme_preference_store.dart';

enum ThemeSaveState { idle, saving, saved, failed }

class ThemeViewModel extends ValueNotifier<ThemeMode> {
  ThemeViewModel(this._store) : super(ThemeMode.system);

  final ThemePreferenceStore _store;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _pendingSave = Future.value();
  final saveState = ValueNotifier<ThemeSaveState>(ThemeSaveState.idle);

  Future<void> load() async {
    if (_disposed) return;
    final revision = ++_revision;
    final mode = await _store.load();
    if (!_disposed && revision == _revision) value = mode;
  }

  Future<void> select(ThemeMode mode) async {
    if (_disposed) return;
    final revision = ++_revision;
    value = mode;
    saveState.value = ThemeSaveState.saving;
    final saving = _pendingSave.then((_) => _store.save(mode));
    // A failed write must not prevent a later user selection being saved.
    _pendingSave = saving.catchError((Object _) {});
    try {
      await saving;
      if (!_disposed && revision == _revision) {
        saveState.value = ThemeSaveState.saved;
      }
    } on Exception {
      if (!_disposed && revision == _revision) {
        saveState.value = ThemeSaveState.failed;
      }
    }
  }

  Future<void> retrySave() async {
    if (!_disposed && saveState.value == ThemeSaveState.failed) {
      await select(value);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    saveState.dispose();
    super.dispose();
  }
}

import 'package:flutter/material.dart';

import '../data/theme_preference_store.dart';

class ThemeViewModel extends ValueNotifier<ThemeMode> {
  ThemeViewModel(this._store) : super(ThemeMode.system);

  final ThemePreferenceStore _store;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _pendingSave = Future.value();

  Future<void> load() async {
    if (_disposed) return;
    final revision = ++_revision;
    final mode = await _store.load();
    if (!_disposed && revision == _revision) value = mode;
  }

  Future<void> select(ThemeMode mode) async {
    if (_disposed) return;
    _revision++;
    value = mode;
    final saving = _pendingSave.then((_) => _store.save(mode));
    // A failed write must not prevent a later user selection being saved.
    _pendingSave = saving.catchError((Object _) {});
    await saving;
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
  test(
    'failed theme persistence keeps the selected mode without throwing',
    () async {
      final store = _DelayedStore()..failNextSave = true;
      final model = ThemeViewModel(store);
      addTearDown(model.dispose);
      await expectLater(model.select(ThemeMode.dark), completes);
      expect(model.value, ThemeMode.dark);
      await model.select(ThemeMode.light);
      expect(store.saved, ThemeMode.light);
    },
  );

  test('failed save completion after disposal is ignored safely', () async {
    final store = _DelayedStore()..firstSave = Completer<void>();
    final model = ThemeViewModel(store);
    final saving = model.select(ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);
    model.dispose();
    final result = expectLater(saving, completes);
    store.firstSave!.completeError(Exception('fixture storage unavailable'));
    await result;
  });

  test('late theme load cannot replace a newer selection', () async {
    final store = _DelayedStore();
    final model = ThemeViewModel(store);
    addTearDown(model.dispose);
    final loading = model.load();
    await model.select(ThemeMode.dark);
    store.loaded.complete(ThemeMode.light);
    await loading;
    expect(model.value, ThemeMode.dark);
  });

  test('theme load completion after disposal is ignored', () async {
    final store = _DelayedStore();
    final model = ThemeViewModel(store);
    final loading = model.load();
    model.dispose();
    store.loaded.complete(ThemeMode.dark);
    await expectLater(loading, completes);
  });

  test(
    'theme saves serialize so a slow earlier choice cannot overwrite the latest',
    () async {
      final store = _DelayedStore()..firstSave = Completer<void>();
      final model = ThemeViewModel(store);
      addTearDown(model.dispose);
      final first = model.select(ThemeMode.dark);
      await Future<void>.delayed(Duration.zero);
      final second = model.select(ThemeMode.light);
      await Future<void>.delayed(Duration.zero);
      expect(model.value, ThemeMode.light);
      expect(store.started, [ThemeMode.dark]);
      store.firstSave!.complete();
      await Future.wait([first, second]);
      expect(store.saved, ThemeMode.light);
    },
  );
}

class _DelayedStore implements ThemePreferenceStore {
  final loaded = Completer<ThemeMode>();
  Completer<void>? firstSave;
  final started = <ThemeMode>[];
  ThemeMode? saved;
  bool failNextSave = false;
  @override
  Future<ThemeMode> load() => loaded.future;
  @override
  Future<void> save(ThemeMode mode) async {
    started.add(mode);
    if (started.length == 1) await firstSave?.future;
    if (failNextSave) {
      failNextSave = false;
      throw Exception('fixture storage unavailable');
    }
    saved = mode;
  }
}

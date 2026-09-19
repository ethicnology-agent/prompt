import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
  testWidgets(
    'failed appearance save shows a safe retry and keeps the choice',
    (tester) async {
      final store = _FailingStore();
      final model = ThemeViewModel(store);
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(home: AppearanceScreen(themeViewModel: model)),
      );
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(model.value, ThemeMode.dark);
      expect(
        find.text(
          'Appearance changed for this session, but could not be saved.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('fixture private storage details'),
        findsNothing,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(store.saved, ThemeMode.dark);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an older failed save cannot replace a newer appearance choice', (
    tester,
  ) async {
    final gate = Completer<void>();
    final store = _FailingStore()..firstGate = gate;
    final model = ThemeViewModel(store);
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(home: AppearanceScreen(themeViewModel: model)),
    );
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.tap(find.text('Light'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(model.value, ThemeMode.light);
    expect(store.saved, ThemeMode.light);
    expect(find.text('Retry'), findsNothing);
  });

  for (final compact in [false, true]) {
    testWidgets('appearance navigation and saved selection compact=$compact', (
      tester,
    ) async {
      final store = InMemoryThemePreferenceStore();
      final model = ThemeViewModel(store);
      addTearDown(model.dispose);
      await tester.binding.setSurfaceSize(
        compact ? const Size(320, 400) : const Size(393, 850),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: model,
          builder: (context, mode, _) => MaterialApp(
            theme: promptTheme(),
            darkTheme: promptDarkTheme(),
            themeMode: mode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
              child: child!,
            ),
            home: SettingsScreen(
              serverLabel: 'Private fixture',
              themeViewModel: model,
              onOpenServer: null,
              onOpenVoice: () {},
              onOpenNotifications: () {},
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Appearance').hitTestable(),
        120,
      );
      expect(find.text('Appearance').hitTestable(), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.byType(AppearanceScreen), findsOneWidget);
      expect(find.widgetWithText(SettingsGroup, 'THEME'), findsOneWidget);
      expect(find.textContaining('Language'), findsNothing);
      expect(find.textContaining('Avatar'), findsNothing);
      expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isFalse);
      for (final option in [
        ThemeMode.dark,
        ThemeMode.light,
        ThemeMode.system,
      ]) {
        final label = appearanceLabel(option);
        final text = find.text(label);
        await tester.scrollUntilVisible(
          text.hitTestable(),
          option == ThemeMode.dark ? 100 : -100,
        );
        expect(text.hitTestable(), findsOneWidget);
        await tester.tap(text);
        await tester.pumpAndSettle();
        expect(model.value, option);
        expect(store.value, option);
        final row = tester.widget<ListTile>(
          find.ancestor(of: text, matching: find.byType(ListTile)),
        );
        expect(row.selected, isTrue);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        if (option != ThemeMode.system) {
          expect(
            Theme.of(tester.element(text)).brightness,
            option == ThemeMode.dark ? Brightness.dark : Brightness.light,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(find.text('Dark').hitTestable(), 100);
      expect(find.text('Dark').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AppearanceScreen), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Appearance').hitTestable(),
        -100,
      );
      expect(find.text('Appearance').hitTestable(), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Dark').hitTestable(), 100);
      expect(
        tester
            .widget<ListTile>(
              find.ancestor(
                of: find.text('Dark'),
                matching: find.byType(ListTile),
              ),
            )
            .selected,
        isTrue,
      );
      final restored = ThemeViewModel(store);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.value, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    });
  }
}

class _FailingStore implements ThemePreferenceStore {
  Completer<void>? firstGate;
  int saves = 0;
  ThemeMode? saved;

  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) async {
    saves++;
    if (saves == 1) {
      await firstGate?.future;
      throw Exception('fixture private storage details');
    }
    saved = mode;
  }
}

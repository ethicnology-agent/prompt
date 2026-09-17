import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'disconnect explains continuing server tasks without changing action dark=$dark',
      (tester) async {
        final model = ThemeViewModel(InMemoryThemePreferenceStore());
        addTearDown(model.dispose);
        final actions = <String>[];
        await tester.binding.setSurfaceSize(const Size(320, 360));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? promptDarkTheme() : promptTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: SettingsScreen(
              serverLabel: 'Private fixture',
              themeViewModel: model,
              onOpenServer: () => actions.add('server'),
              onOpenVoice: () => actions.add('voice'),
              onOpenNotifications: () => actions.add('notifications'),
              onDisconnect: () => actions.add('disconnect'),
            ),
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Disconnect').hitTestable(),
          120,
        );
        final tile = find.widgetWithText(ListTile, 'Disconnect');
        const explanation =
            'Disconnects this device. Tasks already running on the server continue.';
        expect(
          find.descendant(of: tile, matching: find.text(explanation)),
          findsOneWidget,
        );
        expect(tester.widget<Text>(find.text(explanation)).maxLines, isNull);
        expect(actions, isEmpty);
        await tester.tap(find.text('Disconnect'));
        expect(actions, ['disconnect']);
        await tester.pump();
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('grouped settings preserve private actions dark=$dark', (
      tester,
    ) async {
      final model = ThemeViewModel(InMemoryThemePreferenceStore());
      addTearDown(model.dispose);
      final actions = <String>[];
      final theme = dark ? promptDarkTheme() : promptTheme();
      await tester.binding.setSurfaceSize(const Size(393, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: SettingsScreen(
            serverLabel: 'Private fixture',
            themeViewModel: model,
            onOpenServer: () => actions.add('server'),
            onOpenWorkspace: () => actions.add('workspace'),
            onOpenTerminal: () => actions.add('terminal'),
            onOpenVoice: () {},
            onOpenNotifications: () {},
            onDisconnect: () => actions.add('disconnect'),
          ),
        ),
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isFalse);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        SettingsGroup.pageColor(theme),
      );
      expect(find.widgetWithText(SettingsGroup, 'CONNECTION'), findsOneWidget);
      expect(find.widgetWithText(SettingsGroup, 'PREFERENCES'), findsOneWidget);
      expect(find.text('Private fixture'), findsOneWidget);
      expect(find.text('Private connection'), findsOneWidget);
      expect(find.textContaining('QR'), findsNothing);
      expect(find.textContaining('account'), findsNothing);
      expect(find.text('Support us'), findsNothing);
      expect(actions, isEmpty);
      for (final title in [
        'Your server',
        'Browse workspace',
        'Remote terminal',
        'Disconnect',
      ]) {
        await tester.scrollUntilVisible(find.text(title), 120);
        await tester.tap(find.text(title));
        await tester.pump();
      }
      expect(actions, ['server', 'workspace', 'terminal', 'disconnect']);
      expect(find.widgetWithText(SettingsGroup, 'SESSION'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable settings actions remain absent', (tester) async {
    final model = ThemeViewModel(InMemoryThemePreferenceStore());
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: SettingsScreen(
          serverLabel: 'Private fixture',
          themeViewModel: model,
          onOpenServer: null,
          onOpenVoice: () {},
          onOpenNotifications: () {},
          onDisconnect: () {},
        ),
      ),
    );
    expect(find.text('Browse workspace'), findsNothing);
    expect(find.text('Remote terminal'), findsNothing);
    final serverTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Your server'),
        matching: find.byType(ListTile),
      ),
    );
    expect(serverTile.onTap, isNull);
    expect(serverTile.trailing, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings preserve local appearance and explicit navigation', (
    tester,
  ) async {
    final store = InMemoryThemePreferenceStore();
    final model = ThemeViewModel(store);
    addTearDown(model.dispose);
    var voice = 0;
    var notifications = 0;
    await tester.binding.setSurfaceSize(const Size(393, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: SettingsScreen(
          serverLabel: 'Private fixture',
          themeViewModel: model,
          onOpenServer: () {},
          onOpenVoice: () => voice++,
          onOpenNotifications: () => notifications++,
          onDisconnect: () {},
        ),
      ),
    );
    expect(voice, 0);
    expect(notifications, 0);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(model.value, ThemeMode.dark);
    expect(store.value, ThemeMode.dark);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    await tester.ensureVisible(find.text('Voice input'));
    await tester.tap(find.text('Voice input'));
    expect(voice, 1);
    await tester.ensureVisible(find.text('Notifications'));
    await tester.tap(find.text('Notifications'));
    expect(notifications, 1);
    expect(tester.takeException(), isNull);
  });
}

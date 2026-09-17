import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/app/prompt_theme.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
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
    await tester.ensureVisible(find.text('Voice input'));
    await tester.tap(find.text('Voice input'));
    expect(voice, 1);
    await tester.ensureVisible(find.text('Notifications'));
    await tester.tap(find.text('Notifications'));
    expect(notifications, 1);
    expect(tester.takeException(), isNull);
  });
}

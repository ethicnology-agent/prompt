import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/app/prompt_app.dart';
import 'package:prompt/features/settings/data/theme_preference_store.dart';

void main() {
  testWidgets(
    'shows QR-first machine connection with an explicit manual path',
    (WidgetTester tester) async {
      await tester.pumpWidget(PromptApp(lastProfileLoader: () async => null));

      expect(find.text('Connect a machine'), findsOneWidget);
      expect(find.text('Scan pairing QR'), findsOneWidget);
      expect(find.text('Enter details manually'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets('restores a persisted dark theme at startup', (tester) async {
    await tester.pumpWidget(
      PromptApp(
        lastProfileLoader: () async => null,
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      ),
    );
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}

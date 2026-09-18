import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';

void main() {
  testWidgets(
    'search includes provider identity and applies only on explicit confirmation',
    (tester) async {
      String? applied;
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: Scaffold(
            body: SelectionPicker<String>(
              title: 'Model',
              selected: 'provider-a/model',
              options: const [
                SelectionOption(
                  value: 'provider-a/model',
                  label: 'Shared model',
                  description: 'provider-a / model',
                ),
                SelectionOption(
                  value: 'provider-b/model',
                  label: 'Shared model',
                  description: 'provider-b / model',
                ),
              ],
              onApply: (value) => applied = value,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'provider-b');
      await tester.pump();
      expect(find.text('provider-a / model'), findsNothing);
      await tester.tap(find.text('Shared model'));
      await tester.pump();
      final selectedTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Shared model'),
          matching: find.byType(ListTile),
        ),
      );
      expect(selectedTile.selected, isTrue);
      expect(applied, isNull);
      await tester.tap(find.text('Apply'));
      expect(applied, 'provider-b/model');
      await tester.tap(find.text('Cancel'));
      expect(cancelled, isTrue);
      await tester.enterText(find.byType(TextField), 'unmatched');
      await tester.pump();
      expect(find.text('No matching options'), findsOneWidget);
      expect(find.text('Shared model'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      final selected = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((tile) => tile.selected)
          .single;
      expect((selected.subtitle! as Text).data, 'provider-b / model');
    },
  );

  for (final height in [500.0, 90.0]) {
    testWidgets(
      'picker stays scrollable at 320px scale2 usableheight=$height',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: promptDarkTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    height: height,
                    child: SelectionPicker<String>(
                      title: 'Agent',
                      selected: null,
                      options: const [
                        SelectionOption(
                          value: 'build',
                          label: 'Long agent name which remains fully readable',
                        ),
                      ],
                      onApply: (_) {},
                      onCancel: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Apply'),
          40,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Apply').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

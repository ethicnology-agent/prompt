import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final multiple in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'description row supports touch keyboard and disabled state multiple=$multiple dark=$dark',
        (tester) async {
          var selected = false;
          var enabled = true;
          late StateSetter update;
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? promptDarkTheme() : promptTheme(),
                home: Scaffold(
                  body: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(2),
                    ),
                    child: SizedBox(
                      width: 280,
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          update = setState;
                          return ChoiceOptionTile(
                            label: 'Readable choice',
                            description:
                                'A visible explanation that can wrap across several lines.',
                            selected: selected,
                            multiple: multiple,
                            enabled: enabled,
                            onPressed: () =>
                                setState(() => selected = !selected),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            final tile = find.byType(ListTile);
            expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(tile).width, 280);
            expect(
              find.bySemanticsLabel(RegExp('A visible explanation')),
              findsOneWidget,
            );
            await tester.tap(
              find.text(
                'A visible explanation that can wrap across several lines.',
              ),
            );
            await tester.pump();
            expect(selected, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(selected, isFalse);
            update(() => enabled = false);
            await tester.pump();
            expect(tester.widget<ListTile>(tile).onTap, isNull);
            await tester.tap(find.text('Readable choice'));
            expect(selected, isFalse);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}

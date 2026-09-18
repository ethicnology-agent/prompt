import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final enabled in [false, true]) {
      testWidgets(
        'compact choice preserves label and target dark=$dark enabled=$enabled',
        (tester) async {
          final semantics = tester.ensureSemantics();
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? promptDarkTheme() : promptTheme(),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 64,
                    child: CompactChoiceButton(
                      label: 'Very long model name',
                      semanticLabel: 'Model: Very long model name',
                      onPressed: enabled ? () => taps++ : null,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getSize(find.byType(TextButton)).height,
            greaterThanOrEqualTo(48),
          );
          expect(
            tester.getSize(find.byType(TextButton)).width,
            greaterThanOrEqualTo(48),
          );
          final node = tester.getSemantics(
            find.bySemanticsLabel('Model: Very long model name'),
          );
          expect(
            node,
            matchesSemantics(
              label: 'Model: Very long model name',
              isButton: true,
              hasEnabledState: true,
              isEnabled: enabled,
              hasTapAction: enabled,
              hasFocusAction: enabled,
              isFocusable: enabled,
            ),
          );
          expect(find.byTooltip('Model: Very long model name'), findsOneWidget);
          await tester.tap(find.byType(TextButton));
          expect(taps, enabled ? 1 : 0);
          semantics.dispose();
        },
      );
    }
  }
}

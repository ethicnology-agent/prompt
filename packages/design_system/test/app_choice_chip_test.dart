import 'dart:ui' show Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('choice chip is accessible and interactive dark=$dark', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var selected = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? promptDarkTheme() : promptTheme(),
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => AppChoiceChip(
                    label: 'A long visible project filter label',
                    semanticLabel: 'Project filter: example',
                    selected: selected,
                    onSelected: (value) => setState(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        );
        final chip = find.byType(AppChoiceChip);
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
        final label = tester.widget<Text>(
          find.descendant(of: chip, matching: find.byType(Text)),
        );
        expect(label.maxLines, 1);
        expect(label.overflow, TextOverflow.ellipsis);
        expect(
          find.bySemanticsLabel('Project filter: example'),
          findsOneWidget,
        );
        await tester.tap(chip);
        await tester.pump();
        expect(selected, isTrue);
        expect(
          tester
              .getSemantics(find.byType(ChoiceChip))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('disabled choice chip cannot change selection', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: const Scaffold(
          body: AppChoiceChip(
            label: 'Unavailable',
            selected: false,
            onSelected: null,
          ),
        ),
      ),
    );
    expect(
      tester.widget<ChoiceChip>(find.byType(ChoiceChip)).onSelected,
      isNull,
    );
    expect(
      tester.getSize(find.byType(AppChoiceChip)).height,
      greaterThanOrEqualTo(48),
    );
  });
}

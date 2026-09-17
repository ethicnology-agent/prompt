import 'dart:ui' show SemanticsActionEvent, Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets('icon exposes one labelled action with enabled=$enabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: promptTheme(),
            home: Scaffold(
              body: AppIconButton(
                icon: Icons.difference_outlined,
                tooltip: 'Review diff',
                isSelected: true,
                onPressed: enabled ? () => presses++ : null,
              ),
            ),
          ),
        );
        final label = find.bySemanticsLabel('Review diff');
        expect(label, findsOneWidget);
        final node = tester.getSemantics(label);
        expect(node.flagsCollection.isButton, isTrue);
        expect(
          node.flagsCollection.isEnabled,
          enabled ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(node.flagsCollection.isSelected, Tristate.isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), enabled);
        var childCount = 0;
        node.visitChildren((child) {
          childCount++;
          return true;
        });
        expect(
          childCount,
          0,
          reason: 'The label and action must share one accessible node.',
        );
        if (enabled) {
          tester.binding.performSemanticsAction(
            SemanticsActionEvent(
              viewId: tester.view.viewId,
              nodeId: node.id,
              type: SemanticsAction.tap,
            ),
          );
          expect(presses, 1);
        }
      } finally {
        semantics.dispose();
      }
    });
  }
}

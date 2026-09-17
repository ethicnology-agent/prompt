import 'dart:ui' show Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
  theme: dark ? promptDarkTheme() : promptTheme(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 640),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(body: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact row at 320px dark=$dark scale=$scale', (
        tester,
      ) async {
        const title =
            'A very long session title with important context that must remain accessible';
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            host(
              SessionListTile(
                identifier: 'local-session',
                title: title,
                project: 'A long project directory name',
                status: 'Activity unknown',
                timestamp: '2026-09-17',
                onTap: () {},
              ),
              dark: dark,
              scale: scale,
            ),
          );
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(IdentityAvatar)),
            const Size(60, 60),
          );
          final tileOrigin = tester.getTopLeft(find.byType(SessionListTile));
          expect(
            tester.getTopLeft(find.byType(IdentityAvatar)).dx - tileOrigin.dx,
            16,
          );
          expect(tester.getTopLeft(find.text(title)).dx - tileOrigin.dx, 88);
          expect(
            tester.getTopLeft(find.byType(Divider)).dx - tileOrigin.dx,
            88,
          );
          expect(
            tester.widget<Text>(find.text(title)).overflow,
            TextOverflow.ellipsis,
          );
          expect(tester.widget<Text>(find.text(title)).maxLines, 1);
          final node = tester.getSemantics(find.byType(SessionListTile));
          expect(node.label, contains(title));
          expect(node.label, contains('Activity unknown'));
          expect(node.label, isNot(contains('Unread')));
          expect(node.label, isNot(contains('online')));
          expect(
            tester.getSize(find.byType(SessionListTile)).height,
            lessThanOrEqualTo(scale == 1 ? 84 : 150),
          );
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  for (final enabled in [false, true]) {
    testWidgets('selected row exposes one semantic action enabled=$enabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var opened = 0;
        var actions = 0;
        await tester.pumpWidget(
          host(
            SessionListTile(
              identifier: 'local',
              title: 'Session',
              project: 'Project',
              status: 'Working',
              timestamp: '1m',
              selected: true,
              unread: true,
              nested: true,
              statusIcon: Icons.sync,
              inProgress: true,
              onTap: enabled ? () => opened++ : null,
              onLongPress: enabled ? () => actions++ : null,
            ),
          ),
        );
        final node = tester.getSemantics(find.byType(SessionListTile));
        expect(node.flagsCollection.isSelected, Tristate.isTrue);
        expect(node.flagsCollection.isButton, isTrue);
        expect(
          node.flagsCollection.isEnabled,
          enabled ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), enabled);
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.longPress),
          enabled,
        );
        expect(node.label, contains('Unread'));
        expect(node.label, contains('Child session'));
        expect(find.text('1m'), findsNothing);
        expect(
          tester.widget<SpinningIcon>(find.byType(SpinningIcon)).spinning,
          isTrue,
        );
        if (enabled) {
          await tester.tap(find.byType(SessionListTile));
          await tester.longPress(find.byType(SessionListTile));
          expect(opened, 1);
          expect(actions, 1);
        }
      } finally {
        semantics.dispose();
      }
    });
  }
}

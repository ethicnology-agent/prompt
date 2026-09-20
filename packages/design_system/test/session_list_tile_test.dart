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
                avatar: const IdentityAvatar(
                  identifier: 'local-session',
                  size: 48,
                ),
                statusLabel: 'Activity unknown',
                timestamp: '2026-09-17',
                onTap: () {},
              ),
              dark: dark,
              scale: scale,
            ),
          );
          expect(tester.takeException(), isNull);
          final tileOrigin = tester.getTopLeft(find.byType(SessionListTile));
          // Happy draws a 48 mark centred in a 60 slot that starts at 16, so
          // the mark itself lands at 22 and the text column at 88. Measured on
          // Happy 1.7.0, Pixel 6a: avatar bounds x 58 px at density 420.
          expect(
            tester.getSize(find.byType(IdentityAvatar)),
            const Size(48, 48),
          );
          expect(
            tester.getTopLeft(find.byType(IdentityAvatar)).dx - tileOrigin.dx,
            22,
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
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('a working session sweeps its title and keeps the timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SessionListTile(
          identifier: 'local',
          title: 'Session',
          project: 'Project',
          avatar: const IdentityAvatar(identifier: 'local', size: 48),
          state: SessionRowState.thinking,
          statusLabel: 'Working',
          timestamp: '1m',
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(ShimmerText), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a blocked session replaces the timestamp with the amber dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SessionListTile(
          identifier: 'local',
          title: 'Session',
          project: 'Project',
          avatar: const IdentityAvatar(identifier: 'local', size: 48),
          state: SessionRowState.permissionRequired,
          statusLabel: 'Waiting',
          unread: true,
          timestamp: '1m',
          onTap: () {},
        ),
      ),
    );
    expect(find.text('1m'), findsNothing);
    expect(find.byType(ShimmerText), findsNothing);
    final dotFinder = find.byKey(const ValueKey('session-row-dot'));
    final dot = tester.widget<Container>(dotFinder);
    expect((dot.decoration! as BoxDecoration).color, sessionBlockedDotColor);
    expect(tester.getSize(dotFinder), const Size(20, 20));
  });

  testWidgets('a faded session shows neither sweep nor dot', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        host(
          SessionListTile(
            identifier: 'local',
            title: 'Session',
            project: 'Project',
            avatar: const IdentityAvatar(identifier: 'local', size: 48),
            state: SessionRowState.thinking,
            statusLabel: 'Offline',
            unread: true,
            faded: true,
            timestamp: '2h',
            onTap: () {},
          ),
        ),
      );
      expect(find.byType(ShimmerText), findsNothing);
      expect(find.text('2h'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('the third line carries worktree, draft and git counters', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SessionListTile(
          identifier: 'local',
          title: 'Session',
          project: 'Project',
          avatar: const IdentityAvatar(identifier: 'local', size: 48),
          statusLabel: 'Idle',
          worktree: 'feature-branch',
          hasDraft: true,
          changedFiles: 3,
          insertions: 84,
          deletions: 12,
          timestamp: '1m',
          onTap: () {},
        ),
      ),
    );
    expect(find.text('feature-branch'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('+84'), findsOneWidget);
    expect(find.text('−12'), findsOneWidget);
    // No status word is printed; the row spends that line on workspace facts.
    expect(find.text('Idle'), findsNothing);
  });

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
              avatar: const IdentityAvatar(identifier: 'local', size: 48),
              statusLabel: 'Idle',
              timestamp: '1m',
              selected: true,
              unread: true,
              nested: true,
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

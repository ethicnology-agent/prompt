import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/chat/presentation/session_details_screen.dart';
import 'package:prompt/features/sessions/sessions.dart';

final session = OpenCodeSession(
  id: 'session-0123456789abcdef0123456789abcdef',
  projectId: 'project-fixture',
  directory: '/fixture/a-long-private-project-directory/workspace',
  title: 'A session title with enough detail to wrap on narrow screens',
  createdAt: DateTime(2026, 9, 17, 12, 30),
  updatedAt: DateTime(2026, 9, 17, 13, 45),
  parentId: 'parent-fixture',
  agentName: 'fixture-agent',
  modelId: 'fixture-model',
  modelProviderId: 'fixture-provider',
);

Finder get detailsScrollable => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

void main() {
  testWidgets('delete action uses destructive color and explicit callback', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: SessionDetailsScreen(
          session: session,
          backendLabel: 'Codex',
          serverOriginLabel: 'http://10.0.0.10:4096',
          executionLabel: 'Idle',
          onDelete: () => calls++,
        ),
      ),
    );
    final icon = find.byIcon(Icons.delete_outline);
    expect(
      tester.widget<Icon>(icon).color,
      Theme.of(tester.element(icon)).colorScheme.error,
    );
    expect(calls, 0);
    await tester.tap(find.text('Delete session'));
    expect(calls, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('session metadata and actions at 200 percent dark=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? promptDarkTheme() : promptTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionDetailsScreen(
                      session: session,
                      backendLabel: 'Codex · private gateway',
                      serverOriginLabel: 'http://10.0.0.10:4096',
                      executionLabel: 'Activity unknown',
                      onRefresh: () => actions.add('refresh'),
                      onReview: () => actions.add('review'),
                      onOpenArtifacts: () => actions.add('artifacts'),
                    ),
                  ),
                ),
                child: const Text('Open details'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      expect(actions, isEmpty);
      expect(find.byType(SafeArea), findsWidgets);
      for (final title in [
        'Review diff',
        'Refresh transcript',
        'Session artifacts',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title).hitTestable(),
          100,
          scrollable: detailsScrollable,
        );
        expect(find.text(title).hitTestable(), findsOneWidget);
        await tester.tap(find.text(title));
        await tester.pump();
      }
      expect(actions, ['review', 'refresh', 'artifacts']);
      for (final value in [
        session.title,
        'Activity unknown',
        'Codex · private gateway',
        'http://10.0.0.10:4096',
        session.id,
        session.directory,
        session.projectId,
        session.parentId!,
        '09/17/2026 · 12:30',
        '09/17/2026 · 13:45',
        'fixture-agent',
        'fixture-model',
        'fixture-provider',
      ]) {
        await tester.scrollUntilVisible(
          find.text(value).hitTestable(),
          100,
          scrollable: detailsScrollable,
        );
        expect(find.text(value).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('online'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open details'), findsOneWidget);
      expect(find.byType(SessionDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unsupported actions and unknown optional fields are absent', (
    tester,
  ) async {
    final minimal = OpenCodeSession(
      id: 'minimal',
      projectId: 'fixture',
      directory: '/fixture',
      title: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: SessionDetailsScreen(
          session: minimal,
          backendLabel: 'OpenCode · direct',
          serverOriginLabel: 'http://10.0.0.10:4096',
          executionLabel: 'Activity unknown',
        ),
      ),
    );
    expect(find.text('Untitled session'), findsOneWidget);
    expect(find.text('QUICK ACTIONS'), findsNothing);
    expect(find.text('Refresh transcript'), findsNothing);
    expect(find.text('Review diff'), findsNothing);
    expect(find.text('Session artifacts'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Updated').hitTestable(),
      150,
      scrollable: detailsScrollable,
    );
    for (final title in [
      'Parent session ID',
      'Agent',
      'Model',
      'Model provider',
    ]) {
      expect(find.text(title), findsNothing);
    }
    expect(find.text('View Machine'), findsNothing);
    expect(find.text('Fork session'), findsNothing);
    expect(find.text('Delete Session'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final busy in [false, true]) {
    testWidgets('fork action is reachable and disabled only while busy=$busy', (
      tester,
    ) async {
      var forks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: SessionDetailsScreen(
            session: session,
            backendLabel: 'OpenCode',
            serverOriginLabel: 'http://10.0.0.10:4096',
            executionLabel: 'Idle',
            onFork: () => forks++,
            forkInProgress: busy,
          ),
        ),
      );
      final label = busy ? 'Forking session…' : 'Fork session';
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, !busy);
      expect(tile.onTap, busy ? isNull : isNotNull);
      await tester.tap(find.text(label));
      expect(forks, busy ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }
}

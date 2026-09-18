import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/sessions/presentation/new_session_dock.dart';

void main() {
  testWidgets(
    'failed creation keeps the sheet below the status bar with IME open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 851);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      var attempts = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/session') {
          attempts++;
          return http.Response('{}', 500);
        }
        if (request.url.path == '/session') return http.Response('[]', 200);
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"a","worktree":"/fixture/a"},{"id":"b","worktree":"/fixture/b"},{"id":"c","worktree":"/fixture/c"}]',
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final model = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          _NoCredentials(),
        ),
      );
      addTearDown(model.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
            viewModel: model,
            onOpenSession: (_) => fail('Failed creation must not navigate.'),
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New session from draft'));
      await tester.pumpAndSettle();
      final path = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Server project path',
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Title (optional)',
      );
      await tester.enterText(path, '/fixture');
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Keep this title');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create and open'));
      await tester.tap(find.text('Create and open'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(tester.widget<TextField>(path).controller!.text, '/fixture');
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Keep this title',
      );
      final sheet = find.byType(BottomSheet);
      final heading = find.descendant(
        of: sheet,
        matching: find.text('New session'),
      );
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(sheet).dy,
        greaterThanOrEqualTo(24),
        reason: 'Sheet chrome must not occupy the system status bar.',
      );
      expect(tester.getTopLeft(heading).dy, greaterThanOrEqualTo(24));
      expect(
        find.byIcon(Icons.drag_handle_rounded),
        findsNothing,
        reason: 'Dragging is disabled; no handle should suggest otherwise.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('creation keeps input and prevents duplicates while retrying', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<http.Response>();
    var creates = 0;
    OpenCodeSession? opened;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/session') {
        creates++;
        if (creates == 1) return pending.future;
        return http.Response(
          '{"id":"created","projectID":"fixture","directory":"/fixture",'
          '"title":"Keep this title","time":{"created":1,"updated":1}}',
          200,
        );
      }
      return http.Response('[]', 200);
    });
    final model = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        _NoCredentials(),
      ),
    );
    addTearDown(model.dispose);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
          viewModel: model,
          onOpenSession: (session) => opened = session,
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(field('Server project path'), '/fixture');
    await tester.enterText(field('Title (optional)'), 'Keep this title');
    await tester.pumpAndSettle();
    final create = find.widgetWithText(AppButton, 'Create and open');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump(const Duration(milliseconds: 500));
    expect(creates, 1);
    expect(field('Server project path'), findsOneWidget);
    expect(tester.widget<AppButton>(create).busy, isTrue);
    await tester.tap(create);
    await tester.pump();
    expect(creates, 1);
    pending.complete(http.Response('', 503));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Server project path')).controller!.text,
      '/fixture',
    );
    expect(
      tester.widget<TextField>(field('Title (optional)')).controller!.text,
      'Keep this title',
    );
    expect(
      find.text(SessionsFailure.unexpectedResponse.message),
      findsOneWidget,
    );
    expect(opened, isNull);
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(creates, 2);
    expect(opened?.id, 'created');
    expect(field('Server project path'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (size, keyboardHeight) in [
    (const Size(393, 851), 300.0),
    (const Size(851, 393), 150.0),
    (const Size(851, 393), 300.0),
  ]) {
    testWidgets('home draft stays above $keyboardHeight keyboard at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final client = MockClient((_) async => http.Response('[]', 200));
      final model = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          _NoCredentials(),
        ),
      );
      addTearDown(model.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
            viewModel: model,
            onOpenSession: (_) {},
            onOpenSessionWithDraft: (_, _) {},
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final draft = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'What would you like to do?',
      );
      final create = find.byTooltip('New session from draft');
      const text = 'A draft kept through keyboard changes';
      await tester.enterText(draft, text);
      await tester.pumpAndSettle();
      final initialBottom = tester.getBottomRight(create).dy;
      expect(
        tester.getBottomRight(find.byType(NewSessionDock)).dy,
        closeTo(size.height - 12, 1),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        await tester.pumpAndSettle();
        if (size.height - keyboardHeight >= 200) {
          expect(
            tester.getBottomRight(find.byType(NewSessionDock)).dy,
            closeTo(size.height - keyboardHeight - 12, 1),
          );
        }
        expect(
          tester.getBottomRight(create).dy,
          lessThanOrEqualTo(size.height - keyboardHeight),
          reason: 'The draft creation action must not be hidden by the IME.',
        );
        expect(
          tester.getBottomRight(draft).dy,
          lessThanOrEqualTo(size.height - keyboardHeight),
        );
        expect(tester.getTopLeft(draft).dy, greaterThanOrEqualTo(0));
        expect(tester.widget<TextField>(draft).controller!.text, text);
        expect(tester.takeException(), isNull);

        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.getBottomRight(create).dy, closeTo(initialBottom, 1));
        expect(tester.widget<TextField>(draft).controller!.text, text);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('home draft transfers only after explicit session creation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var created = 0;
    var submitted = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/prompt_async')) submitted++;
      if (request.method == 'POST' && request.url.path == '/session') {
        created++;
        return http.Response(
          '{"id":"fixture","projectID":"fixture","directory":"/fixture",'
          '"title":"Draft","time":{"created":1,"updated":1}}',
          200,
        );
      }
      if (request.url.path == '/session' || request.url.path == '/project') {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 200);
    });
    final model = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        _NoCredentials(),
      ),
    );
    String? transferred;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: ServerProfile(origin: Uri.parse('http://10.23.42.1:4096')),
          viewModel: model,
          onOpenSession: (_) =>
              fail('Draft must be transferred with the session.'),
          onOpenSessionWithDraft: (_, draft) => transferred = draft,
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final draft = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'What would you like to do?',
    );
    await tester.enterText(draft, 'An unsent synthetic draft');
    expect(created, 0);
    expect(submitted, 0);
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();
    final path = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Server project path',
    );
    await tester.enterText(path, '/fixture');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create and open'));
    await tester.tap(find.text('Create and open'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(transferred, 'An unsent synthetic draft');
    expect(submitted, 0, reason: 'Create and open does not imply send.');
    expect(tester.widget<TextField>(draft).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    client.close();
  });
}

class _NoCredentials implements CredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
  @override
  Future<void> clearPassword(String profileId) async {}
}

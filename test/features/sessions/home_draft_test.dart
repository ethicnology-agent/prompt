import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/sessions/presentation/new_session_dock.dart';

void main() {
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

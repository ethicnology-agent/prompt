import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
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
    await tester.tap(find.byTooltip('New session'));
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

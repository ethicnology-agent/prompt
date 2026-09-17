import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
  for (final (size, keyboard) in [
    (const Size(393, 851), 300.0),
    (const Size(851, 393), 150.0),
    (const Size(851, 393), 300.0),
  ]) {
    for (final surface in ['create', 'rename', 'search']) {
      testWidgets(
        '$surface accepts text above the $keyboard keyboard at $size',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = const FakeViewPadding(top: 24);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          final client = MockClient((request) async {
            if (request.url.path == '/session') {
              return http.Response(
                '[{"id":"session","projectID":"project",'
                '"directory":"/srv/project","title":"Keyboard fixture",'
                '"time":{"created":1,"updated":1}}]',
                200,
              );
            }
            if (request.url.path == '/project') {
              return http.Response(
                '[{"id":"project","worktree":"/srv/project"}]',
                200,
              );
            }
            if (request.url.path == '/session/status') {
              return http.Response('{"session":{"type":"idle"}}', 200);
            }
            return http.Response('[]', 200);
          });
          final model = SessionsViewModel(
            SessionsRepository(
              OpenCodeSessionsService(OpenCodeTransport(client)),
              const _NoCredentials(),
            ),
          );
          addTearDown(model.dispose);
          addTearDown(client.close);
          await tester.pumpWidget(
            MaterialApp(
              home: SessionsScreen(
                profile: ServerProfile(
                  origin: Uri.parse('http://10.23.42.1:4096'),
                ),
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

          if (surface == 'create') {
            await tester.tap(find.byTooltip('New session from draft'));
          } else if (surface == 'rename') {
            await tester.longPress(find.byType(SessionListTile));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Rename'));
          } else {
            await tester.tap(find.byTooltip('More actions'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.ancestor(
                of: find.text('Filter sessions'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is CheckedPopupMenuItem,
                ),
              ),
            );
          }
          await tester.pumpAndSettle();
          final field = find.byWidgetPredicate((widget) {
            if (widget is! TextField) return false;
            return switch (surface) {
              'create' => widget.decoration?.labelText == 'Server project path',
              'rename' => widget.decoration?.labelText == 'Title',
              _ =>
                widget.decoration?.hintText == 'Search sessions, projects, IDs',
            };
          });
          final input = surface == 'create' ? '/srv/new-project' : 'Keyboard';
          await tester.enterText(field, input);
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          expect(
            tester.getBottomRight(field).dy,
            lessThanOrEqualTo(size.height - keyboard),
          );
          expect(tester.getTopLeft(field).dy, greaterThanOrEqualTo(0));
          expect(tester.widget<TextField>(field).controller!.text, input);
          if (surface != 'search') {
            final action = find.widgetWithText(
              AppButton,
              surface == 'create' ? 'Create and open' : 'Rename',
            );
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            expect(
              tester.getBottomRight(action).dy,
              lessThanOrEqualTo(size.height - keyboard),
            );
          }
          if (surface == 'create') {
            final title = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Title (optional)',
            );
            await tester.ensureVisible(title);
            await tester.enterText(title, 'A named session');
            await tester.pumpAndSettle();
            expect(
              tester.getBottomRight(title).dy,
              lessThanOrEqualTo(size.height - keyboard),
            );
            expect(
              tester.widget<TextField>(title).controller!.text,
              'A named session',
            );
          }
          if (surface == 'search') {
            await tester.enterText(field, 'No session matches this query');
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text('No matching sessions'),
              80,
              scrollable: find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(find.text('No matching sessions'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(field);
            await tester.enterText(field, input);
            await tester.pumpAndSettle();
          }
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field).controller!.text, input);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

class _NoCredentials implements CredentialsStore {
  const _NoCredentials();
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
  @override
  Future<void> clearPassword(String profileId) async {}
}

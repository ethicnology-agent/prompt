import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/data/remote/opencode_session_status_parser.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';
import 'package:prompt/features/sessions/domain/session_activity.dart';
import 'package:prompt/features/sessions/presentation/sessions_view_model.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/domain/scoped_session.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  for (final scoped in [false, true]) {
    test(
      'delete removes descendants from the catalog in its own scope scoped=$scoped',
      () async {
        final records = [
          for (final item in [
            ('parent', null),
            ('child', 'parent'),
            ('grandchild', 'child'),
            ('other', null),
          ])
            <String, Object?>{
              'id': item.$1,
              'parentID': item.$2,
              'projectID': 'project',
              'directory': '/srv/app',
              'title': item.$1,
              'time': {'created': 1000, 'updated': 1000},
            },
        ];
        final client = MockClient(
          (request) async => http.Response(
            request.method == 'GET' && request.url.path == '/session'
                ? jsonEncode(records)
                : 'true',
            200,
          ),
        );
        addTearDown(client.close);
        final model = SessionsViewModel(
          SessionsRepository(
            OpenCodeSessionsService(OpenCodeTransport(client)),
            const _PasswordStore(),
          ),
        );
        addTearDown(model.dispose);
        final sessions = [
          for (final record in records)
            OpenCodeSession(
              id: record['id']! as String,
              parentId: record['parentID'] as String?,
              projectId: 'project',
              directory: '/srv/app',
              title: record['title']! as String,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
        ];
        final otherProfile = ServerProfile(
          origin: Uri.parse('http://10.80.0.2:4096'),
          username: 'opencode',
        );
        model.value = SessionsReady(
          sessions,
          const [],
          catalogGroups: scoped
              ? [
                  SessionCatalogGroup(
                    profile: profile,
                    sessions: sessions,
                    activities: {
                      for (final item in sessions)
                        item.id: SessionActivity.idle,
                    },
                  ),
                  SessionCatalogGroup(
                    profile: otherProfile,
                    sessions: sessions,
                  ),
                ]
              : null,
        );
        expect(await model.delete(profile, sessions.first), isNull);
        final state = model.value as SessionsReady;
        if (scoped) {
          expect(state.catalogGroups!.first.sessions.map((item) => item.id), [
            'other',
          ]);
          expect(state.catalogGroups!.first.activities.keys, ['other']);
          expect(state.catalogGroups!.last.sessions, sessions);
        } else {
          expect(state.sessions.map((item) => item.id), ['other']);
        }
      },
    );
  }

  test(
    'returns a typed suggestion failure for an unavailable capability',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/file') {
          return http.Response('', 404);
        }
        return http.Response('[]', 200);
      });
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );

      final result = await viewModel.suggestDirectories(profile, '/srv/app');

      expect(result, isA<Err<List<String>, SessionsFailure>>());
      expect(
        (result as Err<List<String>, SessionsFailure>).failure,
        SessionsFailure.unexpectedResponse,
      );
      viewModel.dispose();
    },
  );

  test(
    'live status changes update activities without another REST load',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (request.url.path == '/session') {
          return http.Response('[$_sessionJson]', 200);
        }
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"project-1","worktree":"/srv/app"}]',
            200,
          );
        }
        if (request.url.path == '/session/status') {
          return http.Response('{"session-1":{"type":"idle"}}', 200);
        }
        return http.Response('', 404);
      });
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );
      final liveStatuses = ValueNotifier<Map<String, OpenCodeSessionStatus>>(
        {},
      );
      viewModel.bindLiveStatuses(liveStatuses);

      await viewModel.load(profile);
      final requestsAfterLoad = requests;
      liveStatuses.value = const {'session-1': OpenCodeSessionStatusBusy()};
      expect(
        (viewModel.value as SessionsReady).activities['session-1'],
        SessionActivity.working,
      );
      liveStatuses.value = const {'session-1': OpenCodeSessionStatusIdle()};
      expect(
        (viewModel.value as SessionsReady).activities['session-1'],
        SessionActivity.idle,
      );
      expect(requests, requestsAfterLoad);
      viewModel.dispose();
      expect(
        () => liveStatuses.value = const {
          'session-1': OpenCodeSessionStatusBusy(),
        },
        returnsNormally,
      );
      liveStatuses.dispose();
    },
  );

  test('a stale REST completion cannot replace a newer live status', () async {
    final statusGate = Completer<void>();
    final statusStarted = Completer<void>();
    final client = MockClient((request) async {
      if (request.url.path == '/session') {
        return http.Response('[$_sessionJson]', 200);
      }
      if (request.url.path == '/project') {
        return http.Response('[{"id":"project-1","worktree":"/srv/app"}]', 200);
      }
      if (request.url.path == '/session/status') {
        statusStarted.complete();
        await statusGate.future;
        return http.Response('{"session-1":{"type":"idle"}}', 200);
      }
      return http.Response('', 404);
    });
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );
    final liveStatuses = ValueNotifier<Map<String, OpenCodeSessionStatus>>({});
    viewModel.bindLiveStatuses(liveStatuses);
    final load = viewModel.load(profile);
    await statusStarted.future;
    liveStatuses.value = const {'session-1': OpenCodeSessionStatusBusy()};
    statusGate.complete();
    await load;

    expect(
      (viewModel.value as SessionsReady).activities['session-1'],
      SessionActivity.working,
    );
    viewModel.dispose();
    liveStatuses.dispose();
  });
}

const _sessionJson =
    '{"id":"session-1","projectID":"project-1","directory":"/srv/app",'
    '"title":"Session one","time":{"created":1000,"updated":1000}}';

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

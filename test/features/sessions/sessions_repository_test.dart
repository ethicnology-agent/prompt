import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/domain/session_activity.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  test('uses successful project catalogs as authoritative snapshots', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project-a","worktree":"/workspace/alpha"},'
          '{"id":"project-b","worktree":"/workspace/beta"}]',
          200,
        );
      }
      if (request.url.path == '/session' && request.url.query.isEmpty) {
        return http.Response(
          '[{"id":"older","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Older session",'
          '"time":{"created":1000,"updated":2000}},'
          '{"id":"newer","projectID":"project-b",'
          '"directory":"/workspace/beta","title":"Newer session",'
          '"time":{"created":1000,"updated":3000},'
          '"summary":{"files":2,"additions":3,"deletions":1}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/alpha') {
        expect(request.url.queryParameters['scope'], 'project');
        return http.Response(
          '[{"id":"older","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Older session",'
          '"time":{"created":1000,"updated":2000}},'
          '{"id":"alpha-only","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Alpha only",'
          '"time":{"created":1000,"updated":4000}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/beta') {
        expect(request.url.queryParameters['scope'], 'project');
        return http.Response('[]', 200);
      }
      return http.Response('', 404);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoaded>());
    final sessions = (result as SessionsLoaded).sessions;
    expect(sessions.map((session) => session.id), ['alpha-only', 'older']);
  });

  test('maps the session model and agent reported by OpenCode', () async {
    final record = OpenCodeSessionRecord.fromJson({
      'id': 'session-1',
      'projectID': 'project-1',
      'directory': '/workspace/project',
      'title': 'Configured session',
      'agent': 'build',
      'model': {'providerID': 'anthropic', 'id': 'claude-sonnet-4-6'},
      'time': {'created': 1000, 'updated': 2000},
    });

    expect(record.modelProviderId, 'anthropic');
    expect(record.modelId, 'claude-sonnet-4-6');
    expect(record.agentName, 'build');
  });

  test(
    'loads session activity snapshots without making catalog failure',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/session/status') {
          return http.Response(
            '{"session-1":{"type":"busy"},"idle":{"type":"idle"},'
            '"retry":{"type":"retry","attempt":2,"message":"rate limited",'
            '"next":5000},"unknown":{"type":"future"},'
            '"malformed":[]}',
            200,
          );
        }
        if (request.url.path == '/session' || request.url.path == '/project') {
          return http.Response(
            request.url.path == '/project'
                ? '[{"id":"project-1","worktree":"/workspace/project"}]'
                : '[${_sessionJson('session-1')},'
                      '${_sessionJson('idle')},${_sessionJson('retry')},'
                      '${_sessionJson('unknown')},${_sessionJson('malformed')}]',
            200,
          );
        }
        return http.Response('', 404);
      });
      final result = await SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      ).load(profile);

      final loaded = result as SessionsLoaded;
      expect(loaded.activities['session-1'], SessionActivity.working);
      expect(loaded.activities['idle'], SessionActivity.idle);
      expect(loaded.activities['retry'], SessionActivity.retrying);
      expect(loaded.activities['unknown'], SessionActivity.unknown);
      expect(loaded.activities['malformed'], SessionActivity.unknown);
    },
  );

  test('reads the last message when the server reports no status', () async {
    // A server reports only the sessions it runs itself, so a session driven
    // by another OpenCode process is absent from the map. The message stream
    // is shared storage: an assistant message created and not completed is a
    // generation in flight.
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageRequests = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/session/status') {
        return http.Response('{}', 200);
      }
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project-1","worktree":"/workspace/project"}]',
          200,
        );
      }
      if (request.url.path == '/session') {
        return http.Response(
          '[${_sessionJson('generating', updated: now)},'
          '${_sessionJson('finished', updated: now)},'
          '${_sessionJson('ancient', updated: now - 864000000)}]',
          200,
        );
      }
      if (request.url.path.endsWith('/message')) {
        messageRequests.add(request.url.path);
        expect(request.url.queryParameters['limit'], '1');
        final completed = request.url.path.contains('generating')
            ? ''
            : ',"completed":2';
        return http.Response(
          '[{"info":{"id":"m","role":"assistant",'
          '"time":{"created":1$completed}}}]',
          200,
        );
      }
      return http.Response('', 404);
    });

    final loaded =
        await SessionsRepository(
              OpenCodeSessionsService(OpenCodeTransport(client)),
              const _PasswordStore('secret'),
            ).load(profile)
            as SessionsLoaded;

    expect(loaded.activities['generating'], SessionActivity.working);
    expect(loaded.activities['finished'], SessionActivity.idle);
    // Untouched for ten days: not worth a request, and safely idle.
    expect(loaded.activities['ancient'], SessionActivity.idle);
    expect(messageRequests, hasLength(2));
  });

  test(
    'keeps sessions and reports unavailable activity when status fetch fails',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/session/status') {
          return http.Response('', 503);
        }
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"project-1","worktree":"/workspace/project"}]',
            200,
          );
        }
        if (request.url.path == '/session') {
          return http.Response('[${_sessionJson('catalogued')}]', 200);
        }
        return http.Response('', 404);
      });
      final result = await SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      ).load(profile);

      expect(result, isA<SessionsLoaded>());
      final loaded = result as SessionsLoaded;
      expect(loaded.sessions.single.id, 'catalogued');
      expect(loaded.activities['catalogued'], SessionActivity.unavailable);
      expect(loaded.unavailableDirectories, {'/workspace/project'});
    },
  );

  test(
    'separates an unreported session from a directory whose status failed',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"ok-project","worktree":"/srv/ok"},'
            '{"id":"failed-project","worktree":"/srv/failed"}]',
            200,
          );
        }
        if (request.url.path == '/session') {
          return http.Response(
            '[{"id":"ok-busy","projectID":"ok-project",'
            '"directory":"/srv/ok","title":"Busy",'
            '"time":{"created":1000,"updated":1000}},'
            '{"id":"ok-idle","projectID":"ok-project",'
            '"directory":"/srv/ok","title":"Idle",'
            '"time":{"created":1000,"updated":1000}},'
            '{"id":"failed-id","projectID":"failed-project",'
            '"directory":"/srv/failed","title":"Unknown",'
            '"time":{"created":1000,"updated":1000}}]',
            200,
          );
        }
        if (request.url.path == '/session/status' &&
            request.url.queryParameters['directory'] == '/srv/ok') {
          return http.Response('{"ok-busy":{"type":"busy"}}', 200);
        }
        if (request.url.path == '/session/status') {
          return http.Response('', 503);
        }
        return http.Response('', 404);
      });

      final result = await SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      ).load(profile);

      final loaded = result as SessionsLoaded;
      expect(loaded.activities['ok-busy'], SessionActivity.working);
      // Unreported by a reachable server and untouched since the epoch: too
      // stale for a generation to be in flight, so idle without asking.
      expect(loaded.activities['ok-idle'], SessionActivity.idle);
      // Its whole directory could not be queried: a different problem.
      expect(loaded.activities['failed-id'], SessionActivity.unavailable);
      expect(loaded.unavailableDirectories, {'/srv/failed'});
      expect(loaded.sessions, hasLength(3));
    },
  );

  test('suggests matching directories from the server file endpoint', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        '[{"type":"file","absolute":"/workspace/app.txt"},'
        '{"type":"directory","absolute":"/workspace/App"},'
        '{"type":"directory","absolute":"/workspace/apple"},'
        '{"type":"directory","absolute":"/workspace/APP"},'
        '{"type":"directory","absolute":"/workspace/beta"}]',
        200,
      );
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.suggestDirectories(
      profile,
      '/workspace/ap',
    );

    expect(result, isA<Ok<List<String>, SessionsFailure>>());
    expect((result as Ok<List<String>, SessionsFailure>).value, [
      '/workspace/APP',
      '/workspace/App',
      '/workspace/apple',
    ]);
    expect(captured!.url.queryParameters, {
      'directory': '/workspace',
      'path': '.',
    });
    expect(captured!.url.toString(), contains('directory=%2Fworkspace'));
  });

  test('handles Unix root and nested Windows directory queries', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('[]', 200);
    });
    final service = OpenCodeSessionsService(OpenCodeTransport(client));

    await service.suggestDirectories(profile, null, '/');
    await service.suggestDirectories(profile, null, r'C:\Work\pro');

    expect(requests[0].url.queryParameters['directory'], '/');
    expect(requests[1].url.queryParameters['directory'], r'C:\Work');
    expect(requests[1].url.queryParameters['path'], '.');
  });

  test('maps malformed and rejected directory responses', () async {
    final malformed = SessionsRepository(
      OpenCodeSessionsService(
        OpenCodeTransport(MockClient((_) async => http.Response('{}', 200))),
      ),
      const _PasswordStore('secret'),
    );
    final unauthorized = SessionsRepository(
      OpenCodeSessionsService(
        OpenCodeTransport(MockClient((_) async => http.Response('', 401))),
      ),
      const _PasswordStore('secret'),
    );

    final malformedResult = await malformed.suggestDirectories(
      profile,
      '/workspace/a',
    );
    final unauthorizedResult = await unauthorized.suggestDirectories(
      profile,
      '/workspace/a',
    );
    expect(malformedResult, isA<Err<List<String>, SessionsFailure>>());
    expect(
      (malformedResult as Err<List<String>, SessionsFailure>).failure,
      SessionsFailure.unexpectedResponse,
    );
    expect(unauthorizedResult, isA<Err<List<String>, SessionsFailure>>());
    expect(
      (unauthorizedResult as Err<List<String>, SessionsFailure>).failure,
      SessionsFailure.unauthorized,
    );
  });

  test('maps invalid private origins for suggestions and creation', () async {
    final repository = SessionsRepository(
      OpenCodeSessionsService(
        OpenCodeTransport(
          MockClient((_) async => throw StateError('must not send')),
        ),
      ),
      const _PasswordStore('secret'),
    );
    final invalidProfile = ServerProfile(
      origin: Uri.parse('https://example.com'),
      username: 'opencode',
    );

    final suggestions = await repository.suggestDirectories(
      invalidProfile,
      '/workspace/a',
    );
    final creation = await repository.create(invalidProfile, '/workspace/a');

    expect(
      suggestions,
      const Err<List<String>, SessionsFailure>(
        SessionsFailure.unexpectedResponse,
      ),
    );
    expect(
      creation,
      const Err<OpenCodeSession, SessionsFailure>(
        SessionsFailure.unexpectedResponse,
      ),
    );
  });

  test(
    'creates a session in a directory absent from the project catalog',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_sessionJson('new-session'), 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.create(
        profile,
        '  /workspace/new-project  ',
        title: 'New project',
      );

      expect(result, isA<Ok<OpenCodeSession, SessionsFailure>>());
      expect(
        captured!.url.queryParameters['directory'],
        '/workspace/new-project',
      );
      expect(captured!.body, '{"title":"New project"}');
    },
  );

  test('keeps the sessions that loaded when one project fails', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project-a","worktree":"/workspace/alpha"},'
          '{"id":"project-b","worktree":"/workspace/beta"}]',
          200,
        );
      }
      if (request.url.path == '/session' && request.url.query.isEmpty) {
        return http.Response(
          '[{"id":"global","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Global session",'
          '"time":{"created":1000,"updated":2000}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/alpha') {
        return http.Response(
          '[{"id":"alpha-only","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Alpha only",'
          '"time":{"created":1000,"updated":4000}}]',
          200,
        );
      }
      // The second project is unreachable for this load.
      return http.Response('', 500);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoaded>());
    expect((result as SessionsLoaded).sessions.map((session) => session.id), [
      'alpha-only',
    ]);
  });

  test(
    'falls back to the global index only for an unavailable project',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"project-a","worktree":"/workspace/alpha"},'
            '{"id":"project-b","worktree":"/workspace/beta"}]',
            200,
          );
        }
        if (request.url.path == '/session' && request.url.query.isEmpty) {
          return http.Response(
            '[{"id":"beta","projectID":"project-b",'
            '"directory":"/workspace/beta","title":"Beta session",'
            '"time":{"created":1000,"updated":2000}}]',
            200,
          );
        }
        if (request.url.queryParameters['directory'] == '/workspace/alpha') {
          return http.Response('[]', 200);
        }
        return http.Response('', 500);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.load(profile);

      expect((result as SessionsLoaded).sessions.map((session) => session.id), [
        'beta',
      ]);
    },
  );

  test(
    'keeps the global index when the project endpoint is unavailable',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/session') {
          return http.Response(
            '[{"id":"global","projectID":"project-a",'
            '"directory":"/workspace/alpha","title":"Global session",'
            '"time":{"created":1000,"updated":2000}}]',
            200,
          );
        }
        return http.Response('', 500);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.load(profile);

      expect(result, isA<SessionsLoaded>());
      final loaded = result as SessionsLoaded;
      expect(loaded.sessions.single.id, 'global');
      expect(loaded.projects, isEmpty);
    },
  );

  test('maps a rejected session request to an authorization failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('wrong-secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoadFailed>());
    expect(
      (result as SessionsLoadFailed).failure,
      SessionsFailure.unauthorized,
    );
  });

  test(
    'forks a session through the official endpoint and maps the result',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_sessionJson('forked'), 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.fork(profile, _session());

      expect(result, isA<Ok<OpenCodeSession, SessionsFailure>>());
      expect(
        (result as Ok<OpenCodeSession, SessionsFailure>).value.id,
        'forked',
      );
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/session/session-1/fork');
      expect(captured!.url.queryParameters['directory'], '/workspace/project');
    },
  );

  test(
    'shares only a safe returned HTTPS URL and unshares through OpenCode',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return request.method == 'POST'
            ? http.Response(
                _sessionJson(
                  'session-1',
                  shareUrl: 'https://share.example/s/1',
                ),
                200,
              )
            : http.Response('true', 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final shared = await repository.share(profile, _session());
      final unshared = await repository.unshare(profile, _session());

      expect(
        (shared as Ok<String?, SessionsFailure>).value,
        'https://share.example/s/1',
      );
      expect(unshared, isA<Ok<void, SessionsFailure>>());
      expect(requests[0].url.path, '/session/session-1/share');
      expect(requests[1].method, 'DELETE');
      expect(requests[1].url.path, '/session/session-1/share');
    },
  );

  test(
    'reverts only the supplied message ID through the official endpoint',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('true', 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.revert(profile, _session(), 'message-1');

      expect((result as Ok<bool, SessionsFailure>).value, isTrue);
      expect(captured!.url.path, '/session/session-1/revert');
      expect(captured!.url.queryParameters['directory'], '/workspace/project');
      expect(captured!.body, '{"messageID":"message-1"}');
    },
  );

  test('aborts a session before deleting it from OpenCode', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response('[]', 200);
      }
      return request.url.path.endsWith('/abort')
          ? http.Response('false', 200)
          : http.Response('true', 200);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.delete(profile, _session());

    expect(result, isA<Ok<void, SessionsFailure>>());
    expect(requests.map((request) => request.method), [
      'GET',
      'POST',
      'DELETE',
    ]);
    expect(requests[1].url.path, '/session/session-1/abort');
    expect(requests[2].url.path, '/session/session-1');
  });

  test('deletes descendant sessions before their parent', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response(
          '[${_sessionJson('child', parentId: 'session-1')},'
          '${_sessionJson('grandchild', parentId: 'child')}]',
          200,
        );
      }
      return request.url.path.endsWith('/abort')
          ? http.Response('false', 200)
          : http.Response('true', 200);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.delete(profile, _session());

    expect(result, isA<Ok<void, SessionsFailure>>());
    expect(
      requests
          .where((request) => request.method == 'DELETE')
          .map((request) => request.url.path),
      ['/session/grandchild', '/session/child', '/session/session-1'],
    );
  });

  test(
    'reports exact profile and descendant-first IDs to local cleanup',
    () async {
      ServerProfile? cleanedProfile;
      List<String>? cleanedIds;
      final repository = SessionsRepository(
        OpenCodeSessionsService(
          OpenCodeTransport(
            MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                  '[${_sessionJson('child', parentId: 'session-1')}]',
                  200,
                );
              }
              return http.Response('true', 200);
            }),
          ),
        ),
        const _PasswordStore('secret'),
        onSessionsDeleted: (value, ids) async {
          cleanedProfile = value;
          cleanedIds = ids.toList();
        },
      );
      final result = await repository.delete(profile, _session());
      expect(result, isA<Ok<void, SessionsFailure>>());
      expect(cleanedProfile?.id, profile.id);
      expect(cleanedIds, ['child', 'session-1']);
    },
  );

  test(
    'cleans only remotely deleted descendants when a later delete fails',
    () async {
      List<String>? cleanedIds;
      final repository = SessionsRepository(
        OpenCodeSessionsService(
          OpenCodeTransport(
            MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                  '[${_sessionJson('child', parentId: 'session-1')},${_sessionJson('grandchild', parentId: 'child')}]',
                  200,
                );
              }
              if (request.method == 'DELETE' &&
                  request.url.path.endsWith('/grandchild')) {
                return http.Response('true', 200);
              }
              if (request.method == 'DELETE') return http.Response('', 500);
              return http.Response('false', 200);
            }),
          ),
        ),
        const _PasswordStore('secret'),
        onSessionsDeleted: (_, ids) async => cleanedIds = ids.toList(),
      );
      final result = await repository.delete(profile, _session());
      expect(result, isA<Err<void, SessionsFailure>>());
      expect(cleanedIds, ['grandchild']);
    },
  );

  test(
    'local cleanup failure does not convert successful remote deletion',
    () async {
      var cleanupCalls = 0;
      final repository = SessionsRepository(
        OpenCodeSessionsService(
          OpenCodeTransport(
            MockClient((request) async {
              if (request.method == 'GET') return http.Response('[]', 200);
              return request.url.path.endsWith('/abort')
                  ? http.Response('false', 200)
                  : http.Response('true', 200);
            }),
          ),
        ),
        const _PasswordStore('secret'),
        onSessionsDeleted: (_, _) async {
          cleanupCalls++;
          throw StateError('local database unavailable');
        },
      );
      final result = await repository.delete(profile, _session());
      expect(result, isA<Ok<void, SessionsFailure>>());
      expect(cleanupCalls, 1);
    },
  );
}

OpenCodeSession _session() => OpenCodeSession(
  id: 'session-1',
  projectId: 'project-1',
  directory: '/workspace/project',
  title: 'Session',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
);

String _sessionJson(
  String id, {
  String? shareUrl,
  String? parentId,
  int updated = 1000,
}) =>
    '''
{"id":"$id","projectID":"project-1","directory":"/workspace/project",
"title":"Session","time":{"created":1000,"updated":$updated}
${shareUrl == null ? '' : ',"share":{"url":"$shareUrl"}'}
${parentId == null ? '' : ',"parentID":"$parentId"'}}
''';

class _PasswordStore implements CredentialsStore {
  const _PasswordStore(this._password);

  final String? _password;

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => _password;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

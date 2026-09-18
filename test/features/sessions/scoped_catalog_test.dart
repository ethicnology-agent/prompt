import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/data/remote/opencode_session_status_parser.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
  test(
    'same IDs stay scoped through engine switches, rename and deletion',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.model.dispose);
      await fixture.model.load(fixture.source);
      var state = fixture.model.value as SessionsReady;
      final entries = state.entriesFor(fixture.source);
      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry.identity).toSet(), hasLength(2));
      expect(state.projects.map((project) => project.id).toSet(), hasLength(2));
      final claude = entries.singleWhere(
        (entry) => entry.profile.backend == AgentBackend.gatewayClaude,
      );
      await fixture.model.load(claude.profile);
      expect((fixture.model.value as SessionsReady).sessions, hasLength(2));
      await fixture.model.rename(claude.profile, claude.session, 'Renamed');
      state = fixture.model.value as SessionsReady;
      expect(
        state
            .entriesFor(fixture.source)
            .singleWhere(
              (entry) => entry.profile.backend == AgentBackend.gatewayCodex,
            )
            .session
            .title,
        'codex title',
      );
      expect(
        state
            .entriesFor(fixture.source)
            .singleWhere(
              (entry) => entry.profile.backend == AgentBackend.gatewayClaude,
            )
            .session
            .title,
        'Renamed',
      );
      await fixture.model.delete(claude.profile, claude.session);
      expect(
        (fixture.model.value as SessionsReady)
            .entriesFor(fixture.source)
            .single
            .profile
            .backend,
        AgentBackend.gatewayCodex,
      );
      expect(fixture.mutations, [
        '/prompt/claude/session/same',
        '/prompt/claude/session/same',
      ]);
      expect(fixture.credentials.saved, contains(claude.profile.id));
    },
  );

  test(
    'failed engine keeps stale rows visibly unavailable and ignores unscoped SSE',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.model.dispose);
      await fixture.model.load(fixture.source);
      fixture.failClaude = true;
      await fixture.model.load(fixture.source);
      final statuses = ValueNotifier<Map<String, OpenCodeSessionStatus>>({
        'same': const OpenCodeSessionStatusBusy(),
      });
      fixture.model.bindLiveStatuses(statuses);
      var state = fixture.model.value as SessionsReady;
      expect(state.sessions, hasLength(2));
      expect(
        state.catalogGroups!
            .singleWhere(
              (group) => group.profile.backend == AgentBackend.gatewayClaude,
            )
            .failure,
        isNotNull,
      );
      expect(
        state
            .entriesFor(fixture.source)
            .singleWhere(
              (entry) => entry.profile.backend == AgentBackend.gatewayClaude,
            )
            .activity,
        SessionActivity.unavailable,
      );
      expect(
        state
            .entriesFor(fixture.source)
            .singleWhere(
              (entry) => entry.profile.backend == AgentBackend.gatewayCodex,
            )
            .activity,
        SessionActivity.idle,
      );
      fixture.model.unbindLiveStatuses();
      statuses.dispose();
    },
  );

  test(
    'stale same-gateway loads cannot replace a different endpoint catalog',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.model.dispose);
      fixture.pause = Completer<void>();
      final old = fixture.model.load(fixture.source);
      await Future<void>.delayed(Duration.zero);
      final other = ServerProfile(
        origin: Uri.parse('http://10.0.0.9:4097'),
        backend: AgentBackend.gatewayCodex,
      );
      await fixture.model.load(other);
      fixture.pause!.complete();
      await old;
      expect(
        (fixture.model.value as SessionsReady).entriesFor(other),
        hasLength(2),
      );
      expect(
        (fixture.model.value as SessionsReady).entriesFor(fixture.source),
        isEmpty,
      );
      expect(
        (fixture.model.value as SessionsReady)
            .entriesFor(other)
            .every((entry) => entry.profile.origin == other.origin),
        isTrue,
      );
      expect(
        fixture.credentials.saved,
        isNot(
          contains(
            ServerProfile(
              origin: other.origin,
              username: fixture.source.username,
              backend: AgentBackend.gatewayClaude,
            ).id,
          ),
        ),
      );
    },
  );
}

class _Fixture {
  _Fixture() {
    final transport = OpenCodeTransport(
      MockClient((request) async {
        final path = request.url.path;
        if (path == '/prompt/capabilities') {
          if (request.url.host == '10.0.0.5' && pause != null) {
            await pause!.future;
          }
          return _json({
            'protocolVersion': 1,
            'engines': {
              for (final engine in ['codex', 'claude'])
                engine: {
                  'available': true,
                  'features': [
                    'sessions',
                    'text',
                    'abort',
                    'sessionRename',
                    'sessionDelete',
                  ],
                },
            },
          });
        }
        final engine = request.url.pathSegments[1];
        if (failClaude && engine == 'claude') return http.Response('', 503);
        if (path.endsWith('/global/health')) return _json({});
        if (path.endsWith('/project')) {
          return _json([
            {'id': 'same-project', 'worktree': '/workspace'},
          ]);
        }
        if (path.endsWith('/session/status')) {
          return _json({
            'same': {'type': 'idle'},
          });
        }
        if (path.endsWith('/session/same/abort')) return _json(true);
        if (path.endsWith('/session')) {
          return _json([
            {
              'id': 'same',
              'projectID': 'same-project',
              'directory': '/workspace',
              'title': '$engine title',
              'time': {'created': 1, 'updated': engine == 'claude' ? 2 : 1},
            },
          ]);
        }
        if (path.endsWith('/session/same')) {
          mutations.add(path);
          return _json(true);
        }
        return http.Response('', 404);
      }),
    );
    final repository = SessionsRepository(
      OpenCodeSessionsService(transport),
      credentials,
    );
    final connections = ConnectionRepository(
      OpenCodeHealthService(transport),
      credentials,
      InMemoryServerProfileStore(),
    );
    model = SessionsViewModel(
      repository,
      catalogLoader: LoadSessionCatalog(connections, repository),
    );
  }
  final source = ServerProfile(
    origin: Uri.parse('http://10.0.0.5:4097'),
    username: 'operator',
    backend: AgentBackend.gatewayCodex,
  );
  final credentials = _Credentials();
  late final SessionsViewModel model;
  final mutations = <String>[];
  bool failClaude = false;
  Completer<void>? pause;
}

class _Credentials implements CredentialsStore {
  final saved = <String>[];
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {
    saved.add(profileId);
  }
}

http.Response _json(Object value) => http.Response(jsonEncode(value), 200);

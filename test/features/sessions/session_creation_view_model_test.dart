import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/capabilities/capabilities.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/chat/chat.dart';
import 'package:prompt/features/sessions/sessions.dart';

void main() {
  test(
    'queue failure retries same created session and freezes candidate',
    () async {
      final calls = <SessionLaunch>[];
      final fixture = _Fixture(
        queueLaunch: (launch) async {
          calls.add(launch);
          return calls.length > 1;
        },
      );
      addTearDown(fixture.model.dispose);
      await fixture.model.initialize(
        fixture.source,
        directory: '/workspace',
        draft: 'First',
      );
      expect(await fixture.model.create(submitDraft: true), isNull);
      expect(fixture.model.value.queuePending, isTrue);
      fixture.model.updateDraft('Do not overwrite');
      fixture.model.updateDirectory('/different');
      final launch = await fixture.model.create(submitDraft: true);
      expect(launch?.draft, 'First');
      expect(identical(calls.first, calls.last), isTrue);
      expect(fixture.createdEngines, hasLength(1));
    },
  );

  test(
    'pending queue blocks double tap and cancellation releases owned images',
    () async {
      final accepted = Completer<bool>();
      final fixture = _Fixture(queueLaunch: (_) => accepted.future);
      addTearDown(fixture.model.dispose);
      await fixture.model.initialize(
        fixture.source,
        directory: '/workspace',
        draft: 'First',
      );
      final attachment = PromptAttachment(
        name: 'fixture.png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      );
      fixture.model.attachments.value = [attachment];
      final first = fixture.model.create(submitDraft: true);
      expect(await fixture.model.create(submitDraft: true), isNull);
      accepted.complete(false);
      expect(await first, isNull);
      fixture.model.cancelPreparation();
      expect(attachment.isReleased, isTrue);
      expect(fixture.model.value.queuePending, isFalse);
      expect(fixture.createdEngines, hasLength(1));
    },
  );
  test(
    'effort remains model-scoped and unsupported selection blocks creation',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(fixture.source);
      fixture.model.updateOptions(
        const PromptExecutionOptions(
          modelProviderId: 'codex',
          modelId: 'model',
          reasoningEffort: 'dynamic-effort',
        ),
      );
      expect(fixture.model.value.canCreate, isTrue);
      await fixture.model.selectBackend(AgentBackend.gatewayClaude);
      expect(fixture.model.value.options.reasoningEffort, isNull);
      await fixture.model.selectBackend(AgentBackend.gatewayCodex);
      expect(fixture.model.value.options.reasoningEffort, 'dynamic-effort');
      fixture.model.updateOptions(
        const PromptExecutionOptions(
          modelProviderId: 'codex',
          modelId: 'model',
          reasoningEffort: 'unreported',
        ),
      );
      expect(fixture.model.value.optionsValid, isFalse);
      expect(await fixture.model.create(), isNull);
      expect(fixture.createdEngines, isEmpty);
    },
  );
  test(
    'worktree creation is explicit and changes only the chosen directory',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(fixture.source, draft: 'Keep');
      expect(fixture.worktreeCreates, 0);
      await fixture.model.refreshWorktrees();
      expect(fixture.model.value.canCreateWorktree, isTrue);
      expect(fixture.model.value.worktrees, hasLength(1));
      expect(fixture.worktreeCreates, 0);
      await fixture.model.createWorktree('task');
      expect(fixture.worktreeCreates, 1);
      expect(fixture.model.value.directory, '/workspace/task-generated');
      expect(fixture.model.value.backend, AgentBackend.gatewayCodex);
      expect(fixture.model.value.draft, 'Keep');
      expect(fixture.createdEngines, isEmpty);
    },
  );

  test('worktree response cannot override an edited folder', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.model.initialize(fixture.source);
    fixture.worktreeResponse = Completer<http.Response>();
    final pending = fixture.model.refreshWorktrees();
    await Future<void>.delayed(Duration.zero);
    fixture.model.updateDirectory('/workspace/changed');
    fixture.worktreeResponse!.complete(
      http.Response('{"worktrees":[],"canCreate":true}', 200),
    );
    await pending;
    expect(fixture.model.value.directory, '/workspace/changed');
    expect(fixture.model.value.worktreePhase, WorktreePhase.idle);
    expect(fixture.model.value.canCreateWorktree, isFalse);
  });

  test(
    'unsupported and uncertain worktree responses retain creation inputs',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(fixture.source, draft: 'Keep');
      fixture.supportWorktrees = false;
      await fixture.model.refreshWorktrees();
      expect(fixture.model.value.worktreePhase, WorktreePhase.unsupported);
      await fixture.model.createWorktree('task');
      expect(fixture.worktreeCreates, 0);
      fixture.supportWorktrees = true;
      await fixture.model.refreshWorktrees();
      fixture.failWorktree = true;
      await fixture.model.createWorktree('task');
      expect(
        fixture.model.value.worktreeFailure,
        WorktreeFailure.creationUncertain,
      );
      await fixture.model.createWorktree('task');
      expect(fixture.worktreeCreates, 1);
      expect(fixture.model.value.directory, '/workspace');
      expect(fixture.model.value.draft, 'Keep');
    },
  );

  test(
    'direct OpenCode worktrees fail closed without any network request',
    () async {
      final client = MockClient(
        (_) async => throw StateError('No request permitted'),
      );
      addTearDown(client.close);
      final repository = WorktreeRepository(
        WorktreeService(OpenCodeTransport(client)),
        _Credentials(),
      );
      final direct = ServerProfile(
        origin: Uri.parse('http://10.0.0.5:4096'),
        username: 'operator',
      );
      final result = await repository.load(direct, '/workspace');
      expect(result, isA<Err<SessionWorktreeCatalog, WorktreeFailure>>());
      expect((result as Err).failure, WorktreeFailure.unsupported);
    },
  );

  test(
    'known directory fills an empty input but never replaces user input',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(fixture.source);
      expect(fixture.model.value.directory, '/workspace');
      fixture.model.updateDirectory('/workspace/chosen');
      await fixture.model.selectBackend(AgentBackend.gatewayClaude);
      expect(fixture.model.value.directory, '/workspace/chosen');
    },
  );

  test(
    'selection discovers actual engines and preserves per-engine options and draft',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      const codexOptions = PromptExecutionOptions(
        modelProviderId: 'codex',
        modelId: 'model',
        agentName: 'codex',
      );
      await fixture.model.initialize(
        fixture.source,
        directory: '/workspace',
        title: 'Title',
        draft: 'Keep this draft',
        options: codexOptions,
      );
      expect(
        fixture.model.value.backends,
        containsAll([AgentBackend.gatewayClaude, AgentBackend.gatewayCodex]),
      );
      expect(
        fixture.model.value.backends,
        isNot(contains(AgentBackend.gatewayOpenCode)),
      );
      expect(fixture.model.value.canCreate, isTrue);
      await fixture.model.selectBackend(AgentBackend.gatewayClaude);
      expect(fixture.model.value.options.isEmpty, isTrue);
      fixture.model.updateOptions(
        const PromptExecutionOptions(
          modelProviderId: 'claude',
          modelId: 'model',
        ),
      );
      fixture.model.updateDirectory('/workspace/existing-worktree');
      await fixture.model.selectBackend(AgentBackend.gatewayCodex);
      expect(fixture.model.value.options, same(codexOptions));
      expect(fixture.model.value.draft, 'Keep this draft');
      expect(fixture.model.value.directory, '/workspace/existing-worktree');
      expect(
        fixture.createdEngines,
        isEmpty,
        reason: 'Selection must never create or generate.',
      );
    },
  );

  test(
    'target credential remains secure and launch carries the actual selected engine',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(
        fixture.source,
        directory: '/workspace',
        draft: 'First prompt',
      );
      await fixture.model.selectBackend(AgentBackend.gatewayClaude);
      final target = fixture.model.value.profile!;
      expect(target.origin, fixture.source.origin);
      expect(target.username, fixture.source.username);
      expect(target.id, isNot(fixture.source.id));
      expect(fixture.credentials.passwords[target.id], 'synthetic-secret');
      expect(
        fixture.profiles.last?.id,
        fixture.source.id,
        reason: 'Browsing engines must not switch the active profile.',
      );
      final launch = await fixture.model.create(submitDraft: true);
      expect(launch?.profile.backend, AgentBackend.gatewayClaude);
      expect(launch?.session.id, 'claude-new');
      expect(launch?.draft, 'First prompt');
      expect(launch?.submitDraft, isTrue);
      expect(fixture.createdEngines, ['claude']);
      expect(
        await fixture.model.create(submitDraft: true),
        isNull,
        reason: 'An accepted launch must not be recreated by another tap.',
      );
      expect(
        fixture.credentials.passwords[fixture.source.id],
        'synthetic-secret',
      );
      expect(fixture.profiles.last?.id, target.id);
    },
  );

  test(
    'unavailable engine and mismatched options never create a session',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(
        fixture.source,
        directory: '/workspace',
        draft: 'Keep',
      );
      await fixture.model.selectBackend(AgentBackend.gatewayOpenCode);
      expect(
        fixture.model.value.failure,
        SessionCreationFailure.unsupportedBackend,
      );
      expect(await fixture.model.create(), isNull);
      await fixture.model.selectBackend(AgentBackend.gatewayClaude);
      fixture.model.updateOptions(
        const PromptExecutionOptions(
          modelProviderId: 'codex',
          modelId: 'model',
        ),
      );
      expect(fixture.model.value.canCreate, isFalse);
      expect(await fixture.model.create(), isNull);
      expect(fixture.createdEngines, isEmpty);
      expect(fixture.model.value.draft, 'Keep');
    },
  );

  test('late engine response cannot replace the current choice', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.model.initialize(fixture.source, directory: '/workspace');
    fixture.claudeHealth = Completer<http.Response>();
    final pending = fixture.model.selectBackend(AgentBackend.gatewayClaude);
    await Future<void>.delayed(Duration.zero);
    await fixture.model.selectBackend(AgentBackend.gatewayCodex);
    fixture.claudeHealth!.complete(http.Response('{}', 200));
    await pending;
    expect(fixture.model.value.profile?.backend, AgentBackend.gatewayCodex);
    expect(fixture.model.value.capabilities?.models.single.providerId, 'codex');
  });

  test(
    'failed creation retains all inputs and never automatically retries',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.model.initialize(
        fixture.source,
        directory: '/workspace',
        title: 'Keep title',
        draft: 'Keep text',
      );
      fixture.failCreation = true;
      expect(await fixture.model.create(submitDraft: true), isNull);
      expect(
        fixture.model.value.failure,
        SessionCreationFailure.creationUncertain,
      );
      expect(fixture.model.value.directory, '/workspace');
      expect(fixture.model.value.title, 'Keep title');
      expect(fixture.model.value.draft, 'Keep text');
      expect(await fixture.model.create(), isNull);
      expect(fixture.createdEngines, ['codex']);
    },
  );

  test(
    'direct OpenCode cannot forward its credential to a gateway engine',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final direct = ServerProfile(
        origin: fixture.source.origin,
        username: 'operator',
      );
      final result = await fixture.connections.prepareBackend(
        direct,
        AgentBackend.gatewayClaude,
      );
      expect(result, isA<ConnectionFailed>());
      expect(fixture.createdEngines, isEmpty);
      expect(fixture.credentials.passwords.length, 1);
    },
  );
}

class _Fixture {
  _Fixture({Future<bool> Function(SessionLaunch)? queueLaunch}) {
    credentials.passwords[source.id] = 'synthetic-secret';
    profiles.last = source;
    client = MockClient((request) async {
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('operator:synthetic-secret'))}',
      );
      final path = request.url.path;
      if (path == '/prompt/capabilities') {
        return _json({
          'protocolVersion': 1,
          'machine': {'worktrees': supportWorktrees},
          'engines': {
            for (final engine in ['claude', 'codex', 'opencode'])
              engine: {
                'available': engine != 'opencode',
                'features': ['sessions', 'text', 'abort'],
              },
          },
        });
      }
      if (path == '/prompt/worktrees') {
        if (request.method == 'POST') {
          worktreeCreates++;
          if (failWorktree) {
            return http.Response(
              '{"error":"worktree_operation_uncertain"}',
              504,
            );
          }
          return _json({
            'directory': '/workspace/task-generated',
            'branch': 'refs/heads/prompt/fixture',
            'detached': false,
            'locked': false,
          });
        }
        if (worktreeResponse != null) return worktreeResponse!.future;
        return _json({
          'worktrees': [
            {
              'directory': '/workspace',
              'branch': 'refs/heads/main',
              'detached': false,
              'locked': false,
            },
          ],
          'canCreate': true,
        });
      }
      final engine = request.url.pathSegments[1];
      if (path.endsWith('/global/health')) {
        if (engine == 'claude' && claudeHealth != null) {
          return claudeHealth!.future;
        }
        return _json({});
      }
      if (path.endsWith('/project')) {
        return _json([
          {'id': 'project', 'worktree': '/workspace'},
        ]);
      }
      if (path.endsWith('/session/status')) return _json({});
      if (path.endsWith('/session') && request.method == 'POST') {
        createdEngines.add(engine);
        if (failCreation) return http.Response('{}', 503);
        return _json({
          'id': '$engine-new',
          'projectID': 'project',
          'directory': request.url.queryParameters['directory'],
          'title': 'New',
          'time': {'created': 1, 'updated': 1},
        });
      }
      if (path.endsWith('/provider')) {
        return _json({
          'all': [
            {
              'id': engine,
              'models': {
                'model': {
                  'name': 'Available model',
                  'executionOptions': {
                    'version': 1,
                    'reasoningEfforts': [
                      {'id': 'dynamic-effort', 'label': 'Dynamic effort'},
                    ],
                    'defaultReasoningEffortId': 'dynamic-effort',
                  },
                },
              },
            },
          ],
          'connected': [engine],
        });
      }
      if (path.endsWith('/agent')) {
        return _json([
          {'name': engine, 'mode': 'primary'},
        ]);
      }
      return _json([]);
    });
    final transport = OpenCodeTransport(client);
    connections = ConnectionRepository(
      OpenCodeHealthService(transport),
      credentials,
      profiles,
    );
    model = SessionCreationViewModel(
      queueLaunch: queueLaunch,
      connections: connections,
      sessions: SessionsRepository(
        OpenCodeSessionsService(transport),
        credentials,
      ),
      capabilities: CapabilitiesRepository(
        OpenCodeCapabilitiesService(transport),
        credentials,
      ),
      worktrees: WorktreeRepository(WorktreeService(transport), credentials),
    );
  }
  final source = ServerProfile(
    origin: Uri.parse('http://10.0.0.5:4097'),
    username: 'operator',
    backend: AgentBackend.gatewayCodex,
  );
  final credentials = _Credentials();
  final profiles = _Profiles();
  final createdEngines = <String>[];
  Completer<http.Response>? claudeHealth;
  bool failCreation = false;
  bool supportWorktrees = true;
  bool failWorktree = false;
  int worktreeCreates = 0;
  Completer<http.Response>? worktreeResponse;
  late final http.Client client;
  late final ConnectionRepository connections;
  late final SessionCreationViewModel model;
  void dispose() {
    model.dispose();
    client.close();
  }

  http.Response _json(Object value) => http.Response(jsonEncode(value), 200);
}

class _Credentials implements CredentialsStore {
  final passwords = <String, String?>{};
  @override
  Future<String?> readPassword(String profileId) async => passwords[profileId];
  @override
  Future<void> savePassword(String profileId, String? password) async {
    passwords[profileId] = password;
  }

  @override
  Future<void> clearPassword(String profileId) async {
    passwords.remove(profileId);
  }
}

class _Profiles implements ServerProfileStore {
  ServerProfile? last;
  @override
  Future<void> save(ServerProfile profile) async {
    last = profile;
  }

  @override
  Future<ServerProfile?> loadLast() async => last;
  @override
  Future<ServerProfile?> load(String id) async => last?.id == id ? last : null;
}

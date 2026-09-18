import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/reconnect_backoff.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/local/prompt_database.dart' as db;
import 'package:prompt/data/local/prompt_database.dart' show PromptDatabase;
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/data/remote/opencode_session_status_parser.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/session_block_reason.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/queue/data/queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_repository.dart';
import 'package:prompt/features/queue/data/queue_send_coordinator.dart';
import 'package:prompt/features/queue/domain/queue_approval_failure.dart';
import 'package:prompt/features/queue/domain/queue_failure.dart';
import 'package:prompt/features/queue/domain/queue_send_now_failure.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/queue/domain/sse_connection_state.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';

/// Lets Drift's `watch()` timer-scheduled re-query, and any pending
/// microtask chain inside [QueueSendCoordinator] (stream delivery, mocked
/// HTTP round trips, repository writes), reach a fixed point before the
/// next assertion.
Future<void> _settle({int ticks = 25}) async {
  for (var i = 0; i < ticks; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _StaticPasswordStore implements CredentialsStore {
  const _StaticPasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

/// A scripted OpenCode REST backend for `sendPrompt`, `abortSession`, and
/// `sessionStatus`. Each behavior is independently controllable so a test
/// can simulate acceptance, rejection, and transport failure without a
/// real server.
class _ScriptedChatBackend {
  String sessionStatusType = 'idle';
  bool sessionMissing = false;
  int promptAsyncStatusCode = 204;
  int abortStatusCode = 200;
  bool abortReturnValue = true;

  /// Delays every `prompt_async` response until this completes, letting a
  /// test observe the queue mid-send before it settles.
  Completer<void>? promptAsyncGate;

  /// Delays every `GET /session/status` response until this completes,
  /// letting a test observe the coordinator's reconciliation window (see
  /// `SseReconciling`) before the authoritative status actually resolves.
  Completer<void>? sessionStatusGate;

  int promptAsyncCallCount = 0;
  int commandCallCount = 0;
  int abortCallCount = 0;
  int sessionStatusCallCount = 0;
  final List<String> promptAsyncOrder = <String>[];
  Map<String, dynamic>? lastPromptAsyncBody;
  Map<String, dynamic>? lastCommandBody;

  int permissionResponseStatusCode = 200;
  int questionReplyStatusCode = 200;
  int questionRejectStatusCode = 200;
  int permissionResponseCallCount = 0;
  int questionReplyCallCount = 0;
  int questionRejectCallCount = 0;
  String? lastPermissionResponse;
  List<List<String>>? lastQuestionAnswers;
  List<Map<String, dynamic>> pendingPermissions = <Map<String, dynamic>>[];
  Completer<void>? permissionListGate;
  int permissionListCallCount = 0;
  List<Map<String, dynamic>> pendingQuestions = <Map<String, dynamic>>[];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path.replaceFirst(
      RegExp(r'^/prompt/(claude|codex|opencode)'),
      '',
    );
    if (path.endsWith('/message')) return http.Response('[]', 200);
    if (path.endsWith('/prompt_async')) {
      promptAsyncCallCount++;
      lastPromptAsyncBody = jsonDecode(request.body) as Map<String, dynamic>;
      promptAsyncOrder.add(_promptText(request.body));
      final gate = promptAsyncGate;
      if (gate != null) {
        await gate.future;
      }
      return http.Response('', promptAsyncStatusCode);
    }
    if (path.endsWith('/command')) {
      commandCallCount++;
      lastCommandBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 200);
    }
    if (path.endsWith('/abort')) {
      abortCallCount++;
      return http.Response(jsonEncode(abortReturnValue), abortStatusCode);
    }
    if (path.contains('/permissions/')) {
      permissionResponseCallCount++;
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      lastPermissionResponse = decoded['response'] as String;
      return http.Response(jsonEncode(true), permissionResponseStatusCode);
    }
    if (path == '/permission') {
      permissionListCallCount++;
      final snapshot = jsonEncode(pendingPermissions);
      await permissionListGate?.future;
      return http.Response(snapshot, 200);
    }
    if (path == '/question') {
      return http.Response(jsonEncode(pendingQuestions), 200);
    }
    if (path.endsWith('/reply')) {
      questionReplyCallCount++;
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      lastQuestionAnswers = (decoded['answers'] as List)
          .map((entry) => (entry as List).cast<String>())
          .toList();
      return http.Response(jsonEncode(true), questionReplyStatusCode);
    }
    if (path.endsWith('/reject')) {
      questionRejectCallCount++;
      return http.Response(jsonEncode(true), questionRejectStatusCode);
    }
    if (path == '/session/status') {
      sessionStatusCallCount++;
      final gate = sessionStatusGate;
      if (gate != null) {
        await gate.future;
      }
      return http.Response(
        jsonEncode({
          if (!sessionMissing) 'session-1': {'type': sessionStatusType},
        }),
        200,
      );
    }
    return http.Response('', 404);
  }

  String _promptText(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final parts = decoded['parts'] as List<dynamic>;
    final first = parts.first as Map<String, dynamic>;
    return first['text'] as String;
  }
}

/// A minimal SSE transport whose byte stream is entirely test-controlled,
/// so a test can emit `session.status`/`session.idle` events at exact
/// points in its own timeline instead of racing a real connection.
///
/// Every call to [send] (one per [OpenCodeEventService.connect] call, so
/// one per initial connect and per reconnect) opens a fresh controller,
/// tracked in [connectionCount]; [emit] and [dropConnection] always act on
/// the most recently opened one, mirroring how only the latest connection
/// is ever live.
class _ScriptedEventClient extends http.BaseClient {
  final List<StreamController<List<int>>> _controllers =
      <StreamController<List<int>>>[];

  /// The HTTP status the *next* [send] call responds with. Set to a
  /// non-2xx value to simulate a reconnect attempt being rejected before
  /// any event ever streams.
  int nextConnectStatusCode = 200;
  Completer<void>? headersGate;

  /// How many times [send] has been called, i.e. how many connection
  /// attempts (initial connect plus every reconnect) this client has
  /// served.
  int get connectionCount => _controllers.length;
  int subscriptionCount = 0;
  int cancellationCount = 0;

  StreamController<List<int>> get _latest => _controllers.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>(
      onListen: () => subscriptionCount++,
      onCancel: () => cancellationCount++,
    );
    _controllers.add(controller);
    await headersGate?.future;
    return http.StreamedResponse(controller.stream, nextConnectStatusCode);
  }

  void emit(String type, Map<String, dynamic> properties, {String? directory}) {
    final json = jsonEncode({
      'directory': ?directory,
      'payload': {'type': type, 'properties': properties},
    });
    _latest.add(utf8.encode('data: $json\n\n'));
  }

  /// Simulates the current connection dropping: an [error] delivers it as
  /// a stream error (a transport failure); no [error] simply ends the
  /// stream (the server closing the connection).
  void dropConnection({Object? error}) {
    if (_controllers.isEmpty) {
      return;
    }
    if (error != null) {
      _latest.addError(error);
      return;
    }
    unawaited(_latest.close());
  }

  /// Does not await [StreamController.close]: its `done` future only
  /// completes once a listener has drained the close event, but a test
  /// that never activated the coordinator never attaches one.
  @override
  Future<void> close() {
    for (final controller in _controllers) {
      unawaited(controller.close());
    }
    return Future<void>.value();
  }
}

/// A [Timer] factory that records every requested delay and fires the
/// callback on a real, but zero-duration, timer instead of actually
/// waiting — so a test can assert on the backoff policy's growth without
/// slowing down for it. Zero-duration (rather than synchronous) still
/// defers the callback to a later event-loop turn, matching real `Timer`
/// semantics closely enough that reentrancy in
/// `QueueSendCoordinator._beginReconnect` is never a concern.
class _RecordingTimerFactory {
  final List<Duration> requestedDelays = <Duration>[];

  Timer call(Duration duration, void Function() callback) {
    requestedDelays.add(duration);
    return Timer(Duration.zero, callback);
  }
}

class _DelayedPauseDao implements QueuePromptsDao {
  _DelayedPauseDao(this._delegate, this.pauseGate);

  @override
  Future<void> pauseForSessionDeletion(
    String profileId,
    Set<String> sessionIds,
  ) => _delegate.pauseForSessionDeletion(profileId, sessionIds);

  @override
  Future<void> deleteForSessions(String profileId, Set<String> sessionIds) =>
      _delegate.deleteForSessions(profileId, sessionIds);

  final QueuePromptsDao _delegate;
  final Completer<void> pauseGate;
  final List<String> operations = <String>[];

  @override
  Future<db.QueuedPrompt> enqueue({
    required String id,
    required String serverProfileId,
    required String sessionId,
    required String directory,
    required String promptText,
    QueuedOperationType operationType = QueuedOperationType.prompt,
    String? commandName,
    List<QueuedAttachment> attachments = const [],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
    required DateTime now,
  }) => _delegate.enqueue(
    id: id,
    serverProfileId: serverProfileId,
    sessionId: sessionId,
    directory: directory,
    promptText: promptText,
    operationType: operationType,
    commandName: commandName,
    attachments: attachments,
    executionOptions: executionOptions,
    now: now,
  );
  @override
  Future<db.QueuedPrompt> editText({
    required String id,
    required String promptText,
    required DateTime now,
  }) => _delegate.editText(id: id, promptText: promptText, now: now);
  @override
  Future<db.QueuedPrompt> remove(String id) => _delegate.remove(id);
  @override
  Stream<List<db.QueuedPrompt>> watchQueue({
    required String serverProfileId,
    required String sessionId,
  }) => _delegate.watchQueue(
    serverProfileId: serverProfileId,
    sessionId: sessionId,
  );
  @override
  Future<List<db.QueuedPrompt>> reorder({
    required String serverProfileId,
    required String sessionId,
    required List<String> orderedIds,
  }) => _delegate.reorder(
    serverProfileId: serverProfileId,
    sessionId: sessionId,
    orderedIds: orderedIds,
  );
  @override
  Future<db.QueuedPrompt> markSending(String id, {required DateTime now}) =>
      _delegate.markSending(id, now: now);
  @override
  Future<db.QueuedPrompt> markAcknowledged(
    String id, {
    required DateTime now,
  }) => _delegate.markAcknowledged(id, now: now);
  @override
  Future<db.QueuedPrompt> markFailed(
    String id, {
    String? reason,
    required DateTime now,
  }) => _delegate.markFailed(id, reason: reason, now: now);
  @override
  Future<db.QueuedPrompt> markPaused(
    String id, {
    required String reason,
    required DateTime now,
  }) async {
    operations.add('pause-start');
    await pauseGate.future;
    operations.add('pause-done');
    return _delegate.markPaused(id, reason: reason, now: now);
  }

  @override
  Future<db.QueuedPrompt> markQueued(String id, {required DateTime now}) async {
    operations.add('queued');
    return _delegate.markQueued(id, now: now);
  }

  @override
  Future<db.QueuedPrompt> markSubmissionUnknown(
    String id, {
    required DateTime now,
  }) => _delegate.markSubmissionUnknown(id, now: now);
}

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session-1',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  late PromptDatabase database;
  late QueuePromptsRepository queueRepository;
  late _ScriptedChatBackend backend;
  late ChatRepository chatRepository;
  late _ScriptedEventClient eventClient;
  late OpenCodeEventService eventService;
  late QueueSendCoordinator coordinator;
  var nextId = 0;

  setUp(() {
    database = PromptDatabase.forTesting(NativeDatabase.memory());
    nextId = 0;
    queueRepository = QueuePromptsRepository(
      DriftQueuePromptsDao(database),
      idGenerator: () => 'prompt-${nextId++}',
    );
    backend = _ScriptedChatBackend();
    chatRepository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(backend.client)),
      const _StaticPasswordStore(),
    );
    eventClient = _ScriptedEventClient();
    eventService = OpenCodeEventService(OpenCodeTransport(eventClient));
    coordinator = QueueSendCoordinator(
      queueRepository: queueRepository,
      chatRepository: chatRepository,
      eventService: eventService,
      credentialsStore: const _StaticPasswordStore(),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await eventClient.close();
    await database.close();
  });

  test(
    'deletion blocks abort idle dispatch and clears confirmed queue',
    () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      await queueRepository.enqueue(
        profile: profile,
        session: session,
        promptText: 'Abandoned follow-up',
      );
      await _settle();
      final deleteStarted = Completer<void>();
      final deleteGate = Completer<void>();
      final repository = SessionsRepository(
        OpenCodeSessionsService(
          OpenCodeTransport(
            MockClient((request) async {
              if (request.method == 'GET') return http.Response('[]', 200);
              if (request.url.path.endsWith('/abort')) {
                eventClient.emit('session.idle', {'sessionID': session.id});
                await _settle();
                return http.Response('true', 200);
              }
              deleteStarted.complete();
              await deleteGate.future;
              return http.Response('true', 200);
            }),
          ),
        ),
        const _StaticPasswordStore(),
        onSessionsDeleting: (profile, ids) async =>
            await coordinator.prepareSessionDeletion(profile, ids)
                is Ok<void, QueueFailure>,
        onSessionsDeleted: (profile, ids) async {
          expect(
            await queueRepository.deleteForSessions(profile, ids),
            isA<Ok<void, QueueFailure>>(),
          );
        },
      );
      final deletion = repository.delete(profile, session);
      await deleteStarted.future;
      final sendsWhileDeleting = backend.promptAsyncCallCount;
      deleteGate.complete();
      await deletion;
      await _settle();
      expect(sendsWhileDeleting, 0);
      expect(backend.promptAsyncCallCount, 0);
      expect(
        await queueRepository
            .watchQueue(profile: profile, session: session)
            .first,
        isEmpty,
      );
    },
  );

  test(
    'deletion waits for in-flight submission and never sends its follower',
    () async {
      backend.promptAsyncGate = Completer<void>();
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      await queueRepository.enqueue(
        profile: profile,
        session: session,
        promptText: 'already submitted',
      );
      await queueRepository.enqueue(
        profile: profile,
        session: session,
        promptText: 'follower',
      );
      await _settle();
      expect(backend.promptAsyncCallCount, 1);
      var prepared = false;
      final preparation = coordinator
          .prepareSessionDeletion(profile, [session.id])
          .then((result) {
            prepared = true;
            return result;
          });
      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();
      expect(prepared, isFalse);
      backend.promptAsyncGate!.complete();
      expect(await preparation, isA<Ok<void, QueueFailure>>());
      await _settle();
      expect(backend.promptAsyncCallCount, 1);
      final rows = await queueRepository
          .watchQueue(profile: profile, session: session)
          .first;
      expect(rows.first.state, QueuedPromptState.acknowledged);
      expect(rows.last.pauseReason, QueuePauseReason.sessionDeleted);
    },
  );

  test(
    'deletion pause survives DAO and coordinator recreation and reconnect',
    () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      final result = await queueRepository.enqueue(
        profile: profile,
        session: session,
        promptText: 'abandoned',
      );
      final prompt = (result as Ok<QueuedPrompt, QueueFailure>).value;
      await coordinator.prepareSessionDeletion(profile, [session.id]);
      await coordinator.dispose();
      queueRepository = QueuePromptsRepository(DriftQueuePromptsDao(database));
      coordinator = QueueSendCoordinator(
        queueRepository: queueRepository,
        chatRepository: chatRepository,
        eventService: eventService,
        credentialsStore: const _StaticPasswordStore(),
      );
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      eventClient.emit('session.idle', {'sessionID': session.id});
      coordinator.notifyAppInactive();
      coordinator.notifyAppForeground();
      await _settle(ticks: 100);
      expect(backend.promptAsyncCallCount, 0);
      expect(
        await queueRepository.markQueued(prompt.id),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        await queueRepository.enqueue(
          profile: profile,
          session: session,
          promptText: 'late',
        ),
        isA<Err<QueuedPrompt, QueueFailure>>(),
      );
      expect(
        (await queueRepository
                .watchQueue(profile: profile, session: session)
                .first)
            .single
            .pauseReason,
        QueuePauseReason.sessionDeleted,
      );
    },
  );

  for (final engine in [
    AgentBackend.gatewayClaude,
    AgentBackend.gatewayCodex,
  ]) {
    test(
      'native restart ${engine.name} never dispatches a queued prompt to a missing session',
      () async {
        final native = ServerProfile(
          origin: profile.origin,
          username: profile.username,
          backend: engine,
        );
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: native, session: session);
        await _settle();
        expect(coordinator.currentSessionState, isA<SessionBusy>());
        await queueRepository.enqueue(
          profile: native,
          session: session,
          promptText: 'Must remain queued',
        );
        await _settle();
        expect(backend.promptAsyncCallCount, 0);
        coordinator.notifyAppInactive();
        backend.sessionMissing = true;
        coordinator.notifyAppForeground();
        await _settle(ticks: 100);
        expect(coordinator.currentSessionState, isA<SessionExecutionUnknown>());
        expect(backend.sessionStatusCallCount, greaterThan(1));
        expect(backend.promptAsyncCallCount, 0);
        final queue = await queueRepository
            .watchQueue(profile: native, session: session)
            .first;
        expect(queue.single.state, QueuedPromptState.queued);
      },
    );
  }

  Future<QueuedPrompt> enqueue(
    String text, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    final result = await queueRepository.enqueue(
      profile: profile,
      session: session,
      promptText: text,
      executionOptions: executionOptions,
    );
    return (result as Ok<QueuedPrompt, QueueFailure>).value;
  }

  Future<QueuedPrompt> enqueueCommand(String name, String arguments) async {
    final result = await queueRepository.enqueueCommand(
      profile: profile,
      session: session,
      commandName: name,
      arguments: arguments,
    );
    return (result as Ok<QueuedPrompt, QueueFailure>).value;
  }

  Future<List<QueuedPrompt>> currentQueue() {
    return queueRepository.watchQueue(profile: profile, session: session).first;
  }

  group('activate', () {
    test('queues a command while busy and dispatches its official operation '
        'once the session becomes idle', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final command = await enqueueCommand('review', 'lib/');
      await _settle();
      expect(command.operationType, QueuedOperationType.command);
      expect(backend.commandCallCount, 0);
      expect(backend.abortCallCount, 0);

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(backend.commandCallCount, 1);
      expect(backend.lastCommandBody, {
        'command': 'review',
        'arguments': 'lib/',
      });
      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );
    });

    test('reconciles a persisted sending prompt to paused/submissionUnknown '
        'before any dispatch', () async {
      final prompt = await enqueue('first');
      await queueRepository.markSending(prompt.id);
      backend.sessionStatusType = 'idle';

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.submissionUnknown);
      expect(backend.promptAsyncCallCount, 0);
    });

    test('dispatches the queued execution options unchanged', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue(
        'first',
        executionOptions: const PromptExecutionOptions(
          modelProviderId: 'anthropic',
          modelId: 'claude-sonnet-4',
          agentName: 'build',
        ),
      );
      await _settle();

      expect(backend.lastPromptAsyncBody, {
        'parts': [
          {'type': 'text', 'text': 'first'},
        ],
        'model': {'providerID': 'anthropic', 'modelID': 'claude-sonnet-4'},
        'agent': 'build',
      });
    });

    test('dispatches the queue head immediately when the authoritative '
        'status is already idle', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.acknowledged);
      expect(backend.promptAsyncCallCount, 1);
    });
  });

  group('SSE-gated dispatch', () {
    test(
      'late authenticated connection is closed after lifecycle suspension',
      () async {
        final headers = Completer<void>();
        eventClient.headersGate = headers;
        await coordinator.activate(profile: profile, session: session);
        await enqueue('not in background');
        await _settle();
        coordinator.notifyAppInactive();
        headers.complete();
        await _settle();
        expect(coordinator.connectionState.value, isA<SseSuspended>());
        expect(eventClient.cancellationCount, 1);
        expect(backend.promptAsyncCallCount, 0);
      },
    );

    test('idle SSE closes raw transport immediately on suspension', () async {
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      expect(eventClient.cancellationCount, 0);
      coordinator.notifyAppInactive();
      await _settle();
      expect(eventClient.cancellationCount, 1);
    });
    test(
      'delayed SSE headers block dispatch and reconcile missed busy state',
      () async {
        final headers = Completer<void>();
        eventClient.headersGate = headers;
        await coordinator.activate(profile: profile, session: session);
        await enqueue('wait for readiness');
        await _settle();
        expect(eventClient.connectionCount, 1);
        expect(backend.promptAsyncCallCount, 0);
        expect(coordinator.connectionState.value, isNot(isA<SseConnected>()));
        backend.sessionStatusType = 'busy';
        headers.complete();
        await _settle();
        expect(eventClient.subscriptionCount, 1);
        expect(coordinator.currentSessionState, isA<SessionBusy>());
        expect(backend.promptAsyncCallCount, 0);
        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();
        expect(backend.promptAsyncCallCount, 1);
      },
    );

    test(
      'events during post-handshake snapshot win over stale status',
      () async {
        final headers = Completer<void>();
        eventClient.headersGate = headers;
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        final snapshot = Completer<void>();
        backend.sessionStatusGate = snapshot;
        headers.complete();
        await _settle();
        expect(eventClient.subscriptionCount, 1);
        expect(coordinator.connectionState.value, isA<SseReconciling>());
        eventClient.emit('session.status', {
          'sessionID': session.id,
          'status': {'type': 'busy'},
        });
        await enqueue('wait for actual idle');
        await _settle();
        snapshot.complete();
        await _settle();
        expect(coordinator.currentSessionState, isA<SessionBusy>());
        expect(backend.promptAsyncCallCount, 0);
        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();
        expect(backend.promptAsyncCallCount, 1);
      },
    );
    test(
      'fast idle before acceptance response is not overwritten by busy',
      () async {
        final gate = Completer<void>();
        backend.promptAsyncGate = gate;
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        await enqueue('first');
        await enqueue('second');
        await _settle();
        expect(backend.promptAsyncCallCount, 1);
        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();
        gate.complete();
        await _settle();
        expect(backend.promptAsyncCallCount, 2);
        expect(
          (await currentQueue()).map((prompt) => prompt.state),
          everyElement(QueuedPromptState.acknowledged),
        );
      },
    );

    test(
      'gateway error before acceptance response stops queued dispatch',
      () async {
        final gate = Completer<void>();
        backend.promptAsyncGate = gate;
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        await enqueue('first');
        await enqueue('second');
        await _settle();
        eventClient.emit('session.status', {
          'sessionID': session.id,
          'status': {'type': 'error'},
        });
        await _settle();
        gate.complete();
        await _settle();
        expect(coordinator.currentSessionState, isA<SessionExecutionUnknown>());
        expect(backend.promptAsyncCallCount, 1);
        expect((await currentQueue()).last.state, QueuedPromptState.queued);
      },
    );

    test('permission before acceptance response remains blocked', () async {
      final gate = Completer<void>();
      backend.promptAsyncGate = gate;
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      await enqueue('first');
      await enqueue('second');
      await _settle();
      eventClient.emit('permission.updated', {
        'sessionID': session.id,
        'id': 'approval-1',
        'type': 'Bash',
        'title': 'Explicit permission',
      });
      await _settle();
      gate.complete();
      await _settle();
      expect(
        coordinator.currentSessionBlockReason,
        SessionBlockReason.permission,
      );
      expect(backend.promptAsyncCallCount, 1);
      expect((await currentQueue()).last.state, QueuedPromptState.paused);
    });
    test(
      'publishes global activity for another session without reducing chat',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        expect(eventClient.connectionCount, 1);
        expect(eventClient.subscriptionCount, 1);

        eventClient.emit('session.status', {
          'sessionID': 'session-B',
          'status': {'type': 'busy'},
        });
        await _settle();
        expect(
          coordinator.liveStatuses.value['session-B'],
          isA<OpenCodeSessionStatusBusy>(),
        );
        expect(
          coordinator.conversationStateUpdates.value.sessionStates.keys,
          isNot(contains('session-B')),
        );

        eventClient.emit('session.idle', {'sessionID': 'session-B'});
        await _settle();
        expect(
          coordinator.liveStatuses.value['session-B'],
          isA<OpenCodeSessionStatusIdle>(),
        );
        expect(eventClient.connectionCount, 1);
        expect(eventClient.subscriptionCount, 1);
        expect(
          coordinator.conversationStateUpdates.value.sessionStates.keys,
          contains(session.id),
        );
      },
    );

    test(
      'holds the queue while busy and dispatches once session.idle arrives',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();

        await enqueue('first');
        await _settle();
        var queue = await currentQueue();
        expect(queue.single.state, QueuedPromptState.queued);
        expect(backend.promptAsyncCallCount, 0);

        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        queue = await currentQueue();
        expect(queue.single.state, QueuedPromptState.acknowledged);
        expect(backend.promptAsyncCallCount, 1);
      },
    );

    test('ignores SSE events for another session or directory', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      eventClient.emit('session.idle', {'sessionID': 'unrelated-session'});
      eventClient.emit('session.status', {
        'sessionID': session.id,
        'status': {'type': 'idle'},
      }, directory: '/some/other/workspace');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.queued);
      expect(backend.promptAsyncCallCount, 0);
    });

    test('ignores an unmodeled SSE event type', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('session.error', {'sessionID': session.id});
      await _settle();

      await enqueue('first');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.acknowledged);
    });
  });

  group('permission/question blocking', () {
    test(
      'reply invalidates an older pending-permissions snapshot without dispatch',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        await enqueue('queued');
        eventClient.emit('permission.updated', {
          'id': 'first',
          'type': 'bash',
          'sessionID': session.id,
          'title': 'Approve',
        });
        await _settle();
        backend.pendingPermissions = [
          {
            'id': 'second',
            'type': 'bash',
            'sessionID': session.id,
            'title': 'Stale approval',
          },
        ];
        backend.permissionListGate = Completer<void>();
        final count = backend.permissionListCallCount;
        final reply = coordinator.respondToPermission(
          'first',
          PermissionResponse.reject,
        );
        await _settle();
        expect(backend.permissionListCallCount, greaterThan(count));
        eventClient.emit('permission.replied', {
          'sessionID': session.id,
          'requestID': 'second',
          'response': 'reject',
        });
        await _settle();
        backend.permissionListGate!.complete();
        await reply;
        await _settle();
        expect(coordinator.currentPendingApproval, isNull);
        expect(
          coordinator.currentSessionBlockReason,
          SessionBlockReason.permission,
        );
        expect((await currentQueue()).single.state, QueuedPromptState.paused);
        expect(backend.promptAsyncCallCount, 0);
      },
    );
    test('orders a delayed pause before an unblock can resume it', () async {
      final pauseGate = Completer<void>();
      final delayedDao = _DelayedPauseDao(
        DriftQueuePromptsDao(database),
        pauseGate,
      );
      queueRepository = QueuePromptsRepository(
        delayedDao,
        idGenerator: () => 'prompt-delayed',
      );
      await coordinator.dispose();
      coordinator = QueueSendCoordinator(
        queueRepository: queueRepository,
        chatRepository: chatRepository,
        eventService: eventService,
        credentialsStore: const _StaticPasswordStore(),
      );
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      await enqueue('first');
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();
      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();
      pauseGate.complete();
      await _settle(ticks: 100);

      expect(delayedDao.operations, ['pause-start', 'pause-done', 'queued']);
    });

    for (final modern in [false, true]) {
      test(
        'a pending permission (modern=$modern) pauses the queued prompt, blocks dispatch, and '
        'only resumes on an authoritative session.idle event',
        () async {
          backend.sessionStatusType = 'busy';
          await coordinator.activate(profile: profile, session: session);
          await _settle();

          final prompt = await enqueue('first');
          await _settle();
          expect((await currentQueue()).single.state, QueuedPromptState.queued);

          eventClient.emit(modern ? 'permission.asked' : 'permission.updated', {
            'id': 'perm_1',
            'sessionID': session.id,
            if (!modern) ...{
              'type': 'bash',
              'messageID': 'msg_1',
              'title': 'Run a shell command',
            },
            if (modern) ...{
              'permission': 'bash',
              'patterns': ['git status'],
              'always': ['git *'],
            },
            'metadata': <String, dynamic>{},
            'time': {'created': 1700000000000},
          });
          await _settle();

          expect(
            coordinator.currentSessionBlockReason,
            SessionBlockReason.permission,
          );
          var queue = await currentQueue();
          expect(queue.single.id, prompt.id);
          expect(queue.single.state, QueuedPromptState.paused);
          expect(queue.single.pauseReason, QueuePauseReason.permissionPending);
          expect(backend.promptAsyncCallCount, 0);

          // A reply retires the approval UI, but is not a terminal session event.
          eventClient.emit('permission.replied', {
            'sessionID': session.id,
            'requestID': 'perm_1',
            if (modern) 'reply': 'once' else 'response': 'once',
          });
          await _settle();
          expect(coordinator.currentPendingApproval, isNull);
          expect(
            coordinator.currentSessionBlockReason,
            SessionBlockReason.permission,
          );
          expect((await currentQueue()).single.state, QueuedPromptState.paused);
          expect(backend.promptAsyncCallCount, 0);

          eventClient.emit('session.idle', {'sessionID': session.id});
          await _settle();

          expect(coordinator.currentSessionBlockReason, isNull);
          queue = await currentQueue();
          expect(queue.single.state, QueuedPromptState.acknowledged);
          expect(backend.promptAsyncCallCount, 1);
        },
      );
    }

    test('a pending question pauses the queue with questionPending', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'question',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Which option do you want?',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();

      expect(
        coordinator.currentSessionBlockReason,
        SessionBlockReason.question,
      );
      expect(
        (await currentQueue()).single.pauseReason,
        QueuePauseReason.questionPending,
      );

      eventClient.emit('session.status', {
        'sessionID': session.id,
        'status': {'type': 'idle'},
      });
      await _settle();

      expect(coordinator.currentSessionBlockReason, isNull);
      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );
    });

    test('a prompt enqueued while already blocked is paused too, not '
        'dispatched', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'edit',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Edit a file',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();

      await enqueue('queued while blocked');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.permissionPending);
      expect(backend.promptAsyncCallCount, 0);
    });

    test('sendNow rejects a prompt a pending permission already paused, and '
        'never aborts for it', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final prompt = await enqueue('first');
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();
      expect((await currentQueue()).single.state, QueuedPromptState.paused);

      final result = await coordinator.sendNow(prompt.id);

      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.promptNotQueued,
      );
      expect(backend.abortCallCount, 0);

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(coordinator.currentSessionBlockReason, isNull);
      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );
    });

    test('does not disturb a prompt paused for an unrelated reason', () async {
      backend.sessionStatusType = 'busy';
      final stuck = await enqueue('stuck');
      await queueRepository.markSending(stuck.id);
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      expect(
        (await currentQueue()).single.pauseReason,
        QueuePauseReason.submissionUnknown,
      );

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      // The submissionUnknown pause is untouched by the permission block
      // being set and cleared; only a human resumes that one.
      expect(
        (await currentQueue()).single.pauseReason,
        QueuePauseReason.submissionUnknown,
      );
    });
  });

  group('currentPendingApproval', () {
    test('carries the full permission detail while blocked, and clears with '
        'the block on an authoritative session.idle', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      expect(coordinator.currentPendingApproval, isNull);

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run rm -rf /tmp/build',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();

      final detail =
          coordinator.currentPendingApproval as PendingPermissionApproval;
      expect(detail.permissionId, 'perm_1');
      expect(detail.toolType, 'bash');
      expect(detail.title, 'Run rm -rf /tmp/build');

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(coordinator.currentPendingApproval, isNull);
    });

    test('carries the full question detail while blocked', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('question.asked', {
        'id': 'que_1',
        'sessionID': session.id,
        'questions': [
          {
            'question': 'Which database should I use?',
            'header': 'Database choice',
            'options': [
              {'label': 'Postgres', 'description': 'Relational, robust'},
            ],
          },
        ],
      });
      await _settle();

      expect(
        coordinator.currentSessionBlockReason,
        SessionBlockReason.question,
      );
      final detail =
          coordinator.currentPendingApproval as PendingQuestionApproval;
      expect(detail.requestId, 'que_1');
      expect(detail.questions.single.question, 'Which database should I use?');
    });

    test('resets to null once the session is deactivated', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();
      expect(coordinator.currentPendingApproval, isNotNull);

      await coordinator.deactivate();

      expect(coordinator.currentPendingApproval, isNull);
    });
  });

  group('respondToPermission', () {
    test(
      'refetches and presents the next approval without resuming the queue',
      () async {
        backend.sessionStatusType = 'busy';
        backend.pendingPermissions = [
          {
            'id': 'perm_1',
            'type': 'bash',
            'sessionID': session.id,
            'title': 'Run the first command',
          },
        ];
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        await enqueue('blocked prompt');
        await _settle();

        expect(
          coordinator.currentPendingApproval,
          isA<PendingPermissionApproval>(),
        );
        expect((await currentQueue()).single.state, QueuedPromptState.paused);

        backend.pendingPermissions = <Map<String, dynamic>>[];
        backend.pendingQuestions = [
          {
            'id': 'question_2',
            'sessionID': session.id,
            'questions': [
              {
                'question': 'Choose the second option',
                'header': 'Choice',
                'options': [
                  {'label': 'Continue', 'description': 'Continue safely'},
                ],
              },
            ],
          },
        ];

        final firstResult = await coordinator.respondToPermission(
          'perm_1',
          PermissionResponse.once,
        );
        await _settle();

        expect(firstResult, isA<Ok<void, QueueApprovalFailure>>());
        expect(
          coordinator.currentPendingApproval,
          isA<PendingQuestionApproval>(),
        );
        expect(
          coordinator.currentSessionBlockReason,
          SessionBlockReason.question,
        );
        expect((await currentQueue()).single.state, QueuedPromptState.paused);
        expect(backend.promptAsyncCallCount, 0);

        backend.pendingQuestions = <Map<String, dynamic>>[];
        final secondResult = await coordinator.rejectQuestion('question_2');
        await _settle();

        expect(secondResult, isA<Ok<void, QueueApprovalFailure>>());
        expect(coordinator.currentPendingApproval, isNull);
        expect(
          coordinator.currentSessionBlockReason,
          SessionBlockReason.question,
        );
        expect((await currentQueue()).single.state, QueuedPromptState.paused);
        expect(backend.promptAsyncCallCount, 0);

        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        expect(coordinator.currentSessionBlockReason, isNull);
        expect(
          (await currentQueue()).single.state,
          QueuedPromptState.acknowledged,
        );
        expect(backend.promptAsyncCallCount, 1);
      },
    );

    test('fails with noActiveSession when nothing is activated', () async {
      final result = await coordinator.respondToPermission(
        'perm_1',
        PermissionResponse.once,
      );

      expect(
        (result as Err<void, QueueApprovalFailure>).failure,
        QueueApprovalFailure.noActiveSession,
      );
    });

    test('posts the response, clears the pending detail, but leaves the '
        'queue paused until an authoritative session.idle arrives', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      await enqueue('first');
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();

      final result = await coordinator.respondToPermission(
        'perm_1',
        PermissionResponse.always,
      );
      await _settle();

      expect(result, isA<Ok<void, QueueApprovalFailure>>());
      expect(backend.permissionResponseCallCount, 1);
      expect(backend.lastPermissionResponse, 'always');

      // The dock's content is gone immediately...
      expect(coordinator.currentPendingApproval, isNull);
      // ...but the queue itself is still paused: only an authoritative
      // session.status/session.idle event may resume it.
      expect(
        coordinator.currentSessionBlockReason,
        SessionBlockReason.permission,
      );
      expect((await currentQueue()).single.state, QueuedPromptState.paused);
      expect(backend.promptAsyncCallCount, 0);

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(coordinator.currentSessionBlockReason, isNull);
      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );
    });

    test('surfaces a rejected request as requestFailed', () async {
      backend.sessionStatusType = 'busy';
      backend.permissionResponseStatusCode = 401;
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();

      final result = await coordinator.respondToPermission(
        'perm_1',
        PermissionResponse.once,
      );

      expect(
        (result as Err<void, QueueApprovalFailure>).failure,
        QueueApprovalFailure.requestFailed,
      );
      // A failed submission never clears the detail: there is nothing new
      // to show, but also nothing resolved yet.
      expect(coordinator.currentPendingApproval, isNotNull);
    });
  });

  group('replyToQuestion and rejectQuestion', () {
    test('replyToQuestion posts every answer and clears the pending detail '
        'only, leaving the block until session.idle', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      await enqueue('first');
      await _settle();

      eventClient.emit('question.asked', {
        'id': 'que_1',
        'sessionID': session.id,
        'questions': [
          {
            'question': 'Which database should I use?',
            'header': 'Database choice',
            'options': [
              {'label': 'Postgres', 'description': 'Relational, robust'},
            ],
          },
        ],
      });
      await _settle();

      final result = await coordinator.replyToQuestion('que_1', [
        ['Postgres'],
      ]);
      await _settle();

      expect(result, isA<Ok<void, QueueApprovalFailure>>());
      expect(backend.questionReplyCallCount, 1);
      expect(backend.lastQuestionAnswers, [
        ['Postgres'],
      ]);
      expect(coordinator.currentPendingApproval, isNull);
      expect(
        coordinator.currentSessionBlockReason,
        SessionBlockReason.question,
      );
      expect((await currentQueue()).single.state, QueuedPromptState.paused);

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );
    });

    test('rejectQuestion posts the rejection and clears the pending detail '
        'only', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('question.asked', {
        'id': 'que_1',
        'sessionID': session.id,
        'questions': [
          {
            'question': 'Which database should I use?',
            'header': 'Database choice',
            'options': <Map<String, dynamic>>[],
          },
        ],
      });
      await _settle();

      final result = await coordinator.rejectQuestion('que_1');
      await _settle();

      expect(result, isA<Ok<void, QueueApprovalFailure>>());
      expect(backend.questionRejectCallCount, 1);
      expect(coordinator.currentPendingApproval, isNull);
      expect(
        coordinator.currentSessionBlockReason,
        SessionBlockReason.question,
      );
    });

    test('replyToQuestion fails with noActiveSession when nothing is '
        'activated', () async {
      final result = await coordinator.replyToQuestion('que_1', [
        ['Postgres'],
      ]);

      expect(
        (result as Err<void, QueueApprovalFailure>).failure,
        QueueApprovalFailure.noActiveSession,
      );
    });

    test('rejectQuestion fails with noActiveSession when nothing is '
        'activated', () async {
      final result = await coordinator.rejectQuestion('que_1');

      expect(
        (result as Err<void, QueueApprovalFailure>).failure,
        QueueApprovalFailure.noActiveSession,
      );
    });
  });

  group('transport-uncertain failures', () {
    test('a prompt_async failure pauses the prompt as submissionUnknown '
        'without retrying', () async {
      backend.sessionStatusType = 'idle';
      backend.promptAsyncStatusCode = 500;
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.submissionUnknown);
      expect(backend.promptAsyncCallCount, 1);

      // No auto retry, even after further idle/queue activity settles.
      eventClient.emit('session.status', {
        'sessionID': session.id,
        'status': {'type': 'idle'},
      });
      await _settle();
      expect(backend.promptAsyncCallCount, 1);
    });

    test('a pending submissionUnknown prompt blocks further automatic '
        'dispatch until resumed', () async {
      backend.sessionStatusType = 'idle';
      final stuck = await enqueue('stuck');
      await queueRepository.markSending(stuck.id);

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final next = await enqueue('next');
      await _settle();

      var queue = await currentQueue();
      expect(
        queue.firstWhere((p) => p.id == next.id).state,
        QueuedPromptState.queued,
      );
      expect(backend.promptAsyncCallCount, 0);

      await queueRepository.markQueued(stuck.id);
      await _settle();

      queue = await currentQueue();
      expect(
        queue.firstWhere((p) => p.id == stuck.id).state,
        QueuedPromptState.acknowledged,
      );
      expect(
        queue.firstWhere((p) => p.id == next.id).state,
        QueuedPromptState.queued,
      );

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();
      queue = await currentQueue();
      expect(
        queue.firstWhere((p) => p.id == next.id).state,
        QueuedPromptState.acknowledged,
      );
    });
  });

  test('a normal enqueue never triggers an abort', () async {
    backend.sessionStatusType = 'busy';
    await coordinator.activate(profile: profile, session: session);
    await _settle();

    await enqueue('first');
    await _settle();
    await enqueue('second');
    await _settle();

    expect(backend.abortCallCount, 0);

    eventClient.emit('session.idle', {'sessionID': session.id});
    await _settle();

    expect(backend.abortCallCount, 0);
  });

  group('conversationStateUpdates', () {
    test(
      'reflects a message.updated followed by message.part.updated',
      () async {
        backend.sessionStatusType = 'idle';
        await coordinator.activate(profile: profile, session: session);
        await _settle();

        eventClient.emit('message.updated', {
          'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
        });
        eventClient.emit('message.part.updated', {
          'part': {
            'id': 'part-1',
            'messageID': 'msg-1',
            'sessionID': session.id,
            'type': 'text',
            'text': 'Hello from SSE',
          },
        });
        await _settle();

        final state = coordinator.conversationStateUpdates.value;
        final message = state.messages['msg-1'];
        expect(message, isNotNull);
        expect(message!.role, ConversationRole.assistant);
        final part = message.parts.single as TextMessagePart;
        expect(part.text, 'Hello from SSE');
      },
    );

    test('ignores an SSE event for another session', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('message.updated', {
        'info': {
          'id': 'msg-1',
          'sessionID': 'unrelated-session',
          'role': 'assistant',
        },
      });
      await _settle();

      expect(coordinator.conversationStateUpdates.value.messages, isEmpty);
    });

    test('resets to empty once the session is deactivated', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('message.updated', {
        'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
      });
      await _settle();
      expect(coordinator.conversationStateUpdates.value.messages, isNotEmpty);

      await coordinator.deactivate();

      expect(coordinator.conversationStateUpdates.value.messages, isEmpty);
    });
  });

  group('sendNow', () {
    test('fails with noActiveSession when nothing is activated', () async {
      final result = await coordinator.sendNow('missing');

      expect(result, isA<Err<void, QueueSendNowFailure>>());
      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.noActiveSession,
      );
    });

    test('fails with promptNotFound for an unknown id', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final result = await coordinator.sendNow('missing');

      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.promptNotFound,
      );
      expect(backend.abortCallCount, 0);
    });

    test('fails with promptNotQueued for a prompt that already sent', () async {
      backend.sessionStatusType = 'idle';
      final prompt = await enqueue('first');
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );

      final result = await coordinator.sendNow(prompt.id);

      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.promptNotQueued,
      );
      expect(backend.abortCallCount, 0);
    });

    test('explicitly aborts, waits for idle, then dispatches the chosen '
        'prompt ahead of the queue head', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final first = await enqueue('first prompt');
      final second = await enqueue('second prompt');
      await _settle();

      final sendNowResult = await coordinator.sendNow(second.id);
      await _settle();

      expect(sendNowResult, isA<Ok<void, QueueSendNowFailure>>());
      expect(backend.abortCallCount, 1);
      // Still busy: nothing dispatches until idle is observed.
      expect(backend.promptAsyncCallCount, 0);
      expect(
        (await currentQueue()).firstWhere((p) => p.id == first.id).state,
        QueuedPromptState.queued,
      );

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(backend.promptAsyncOrder, isNotEmpty);
      expect(backend.promptAsyncOrder.first, 'second prompt');
      final secondRow = (await currentQueue()).firstWhere(
        (p) => p.id == second.id,
      );
      expect(secondRow.state, QueuedPromptState.acknowledged);
    });

    test(
      'surfaces an abort failure without blocking later normal dispatch',
      () async {
        backend.sessionStatusType = 'busy';
        backend.abortStatusCode = 401;
        await coordinator.activate(profile: profile, session: session);
        await _settle();

        final prompt = await enqueue('first');
        await _settle();

        final result = await coordinator.sendNow(prompt.id);
        await _settle();

        expect(
          (result as Err<void, QueueSendNowFailure>).failure,
          QueueSendNowFailure.abortFailed,
        );
        expect(backend.promptAsyncCallCount, 0);

        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        expect(
          (await currentQueue()).single.state,
          QueuedPromptState.acknowledged,
        );
      },
    );
  });

  group('deactivate and reactivate', () {
    test('a dispatch left in flight by deactivate is reconciled on the next '
        'activation instead of writing a stale outcome', () async {
      backend.sessionStatusType = 'idle';
      final gate = Completer<void>();
      backend.promptAsyncGate = gate;

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      var queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.sending);

      await coordinator.deactivate();
      gate.complete();
      await _settle();

      // The stale continuation must not write an acknowledgment for a
      // session that is no longer active.
      queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.sending);

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.submissionUnknown);
    });

    test(
      'reactivating a session cancels the previous SSE subscription',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        await enqueue('first');
        await _settle();

        await coordinator.deactivate();
        await _settle();

        // An event delivered after deactivation must not resurrect dispatch.
        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        expect(backend.promptAsyncCallCount, 0);
        expect((await currentQueue()).single.state, QueuedPromptState.queued);
      },
    );
  });

  test(
    'dispose tears down the active session and rejects reactivation',
    () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await coordinator.dispose();

      expect(
        () => coordinator.activate(profile: profile, session: session),
        throwsStateError,
      );
    },
  );

  group('connectionState', () {
    test(
      'starts suspended, then reports connected once activate settles',
      () async {
        expect(coordinator.connectionState.value, isA<SseSuspended>());

        backend.sessionStatusType = 'idle';
        await coordinator.activate(profile: profile, session: session);
        await _settle();

        expect(coordinator.connectionState.value, isA<SseConnected>());
      },
    );

    test('reports suspended again once deactivated', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await coordinator.deactivate();

      expect(coordinator.connectionState.value, isA<SseSuspended>());
    });
  });

  group('app lifecycle: inactive and foreground', () {
    test(
      'notifyAppInactive cancels the live SSE subscription, suspends the '
      'connection, and stops reconnecting until foreground resumes',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        expect(coordinator.connectionState.value, isA<SseConnected>());
        final connectionsBeforeInactive = eventClient.connectionCount;

        coordinator.notifyAppInactive();
        await _settle();

        expect(coordinator.connectionState.value, isA<SseSuspended>());

        // An event on the connection this coordinator just abandoned, and
        // a fresh enqueue, must never dispatch anything while inactive —
        // and never trigger a reconnect either.
        eventClient.emit('session.idle', {'sessionID': session.id});
        await enqueue('queued while inactive');
        await _settle();

        expect((await currentQueue()).single.state, QueuedPromptState.queued);
        expect(backend.promptAsyncCallCount, 0);
        expect(eventClient.connectionCount, connectionsBeforeInactive);
      },
    );

    test('notifyAppForeground reconnects and reconciles the authoritative '
        'session status before any dispatch resumes', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      coordinator.notifyAppInactive();
      await _settle();

      final prompt = await enqueue('queued while inactive');
      await _settle();
      expect((await currentQueue()).single.state, QueuedPromptState.queued);

      // Gates the status refetch so the reconciliation window (and the
      // fact that it blocks dispatch) is directly observable, instead
      // of racing a REST call that resolves within the same event-loop
      // turn.
      final gate = Completer<void>();
      backend.sessionStatusGate = gate;
      final statusCallsBeforeResume = backend.sessionStatusCallCount;

      coordinator.notifyAppForeground();
      await _settle();

      expect(coordinator.connectionState.value, isA<SseReconciling>());
      expect(backend.sessionStatusCallCount, statusCallsBeforeResume + 1);
      expect((await currentQueue()).single.state, QueuedPromptState.queued);
      expect(backend.promptAsyncCallCount, 0);

      gate.complete();
      await _settle();

      expect(coordinator.connectionState.value, isA<SseConnected>());
      final row = (await currentQueue()).firstWhere((p) => p.id == prompt.id);
      expect(row.state, QueuedPromptState.acknowledged);
      expect(backend.promptAsyncCallCount, 1);
    });

    test('notifyAppForeground is a no-op without an active session', () async {
      expect(() => coordinator.notifyAppForeground(), returnsNormally);
      expect(coordinator.connectionState.value, isA<SseSuspended>());
    });
  });

  group('dropped SSE stream', () {
    test(
      'an unexpected drop while foreground schedules a bounded reconnect, '
      'surfaced as reconnecting, and reconciles before dispatch resumes',
      () async {
        const backoffPolicy = ReconnectBackoffPolicy(
          initialDelay: Duration(milliseconds: 5),
          maxDelay: Duration(milliseconds: 40),
          maxAttempts: 3,
        );
        final timerFactory = _RecordingTimerFactory();
        final reconnectCoordinator = QueueSendCoordinator(
          queueRepository: queueRepository,
          chatRepository: chatRepository,
          eventService: eventService,
          credentialsStore: const _StaticPasswordStore(),
          backoffPolicy: backoffPolicy,
          reconnectTimerFactory: timerFactory.call,
        );

        backend.sessionStatusType = 'idle';
        await reconnectCoordinator.activate(profile: profile, session: session);
        await _settle();
        expect(reconnectCoordinator.connectionState.value, isA<SseConnected>());

        final gate = Completer<void>();
        backend.sessionStatusGate = gate;

        // Never silently discarded: the drop is surfaced, not swallowed.
        // A single `_settle()` reliably observes the reconnect having been
        // *scheduled* (recorded synchronously, from the drop callback
        // itself), but not necessarily still waiting: the fake timer
        // factory below fires on a real (if zero-duration) `Timer`, whose
        // exact interleaving against `_settle`'s own zero-duration delays
        // is not guaranteed, so the state may already have moved on to
        // `SseReconciling` by the time this assertion runs.
        eventClient.dropConnection(error: const OpenCodeTransportFailure(500));
        await _settle();

        expect(timerFactory.requestedDelays, hasLength(1));
        expect(
          reconnectCoordinator.connectionState.value,
          anyOf(isA<SseReconnecting>(), isA<SseReconciling>()),
        );

        // Lets the recorded (but not really waited-for) reconnect timer
        // fire and open a fresh connection.
        await _settle();

        expect(eventClient.connectionCount, 2);
        expect(
          reconnectCoordinator.connectionState.value,
          isA<SseReconciling>(),
        );

        await enqueue('missed during the drop');
        await _settle();
        expect((await currentQueue()).single.state, QueuedPromptState.queued);
        expect(backend.promptAsyncCallCount, 0);

        gate.complete();
        await _settle();

        expect(reconnectCoordinator.connectionState.value, isA<SseConnected>());
        expect(
          (await currentQueue()).single.state,
          QueuedPromptState.acknowledged,
        );

        await reconnectCoordinator.dispose();
      },
    );

    test('a stream simply ending (no error) is treated as a drop too, and '
        'reconnects', () async {
      final timerFactory = _RecordingTimerFactory();
      final reconnectCoordinator = QueueSendCoordinator(
        queueRepository: queueRepository,
        chatRepository: chatRepository,
        eventService: eventService,
        credentialsStore: const _StaticPasswordStore(),
        reconnectTimerFactory: timerFactory.call,
      );

      backend.sessionStatusType = 'idle';
      await reconnectCoordinator.activate(profile: profile, session: session);
      await _settle();
      expect(eventClient.connectionCount, 1);

      eventClient.dropConnection();
      await _settle();

      // Exactly one reconnect was scheduled (never silently ignored),
      // and it opened exactly one fresh connection — not two, which a
      // regression re-processing the same drop twice would produce.
      expect(timerFactory.requestedDelays, hasLength(1));
      expect(eventClient.connectionCount, 2);
      expect(reconnectCoordinator.connectionState.value, isA<SseConnected>());

      await reconnectCoordinator.dispose();
    });

    test('stops retrying once the backoff policy is exhausted, surfaced as '
        'disconnected', () async {
      const backoffPolicy = ReconnectBackoffPolicy(
        initialDelay: Duration(milliseconds: 5),
        maxDelay: Duration(milliseconds: 10),
        maxAttempts: 2,
      );
      final timerFactory = _RecordingTimerFactory();
      final reconnectCoordinator = QueueSendCoordinator(
        queueRepository: queueRepository,
        chatRepository: chatRepository,
        eventService: eventService,
        credentialsStore: const _StaticPasswordStore(),
        backoffPolicy: backoffPolicy,
        reconnectTimerFactory: timerFactory.call,
      );

      backend.sessionStatusType = 'idle';
      await reconnectCoordinator.activate(profile: profile, session: session);
      await _settle();

      // Every reconnect attempt is rejected outright at the transport
      // level, so each one drops again on its own without another
      // explicit `dropConnection` call.
      eventClient.nextConnectStatusCode = 500;
      eventClient.dropConnection(error: const OpenCodeTransportFailure(500));

      for (var i = 0; i < 8; i++) {
        await _settle();
        if (reconnectCoordinator.connectionState.value is SseDisconnected) {
          break;
        }
      }

      expect(
        reconnectCoordinator.connectionState.value,
        isA<SseDisconnected>(),
      );
      expect(
        timerFactory.requestedDelays,
        hasLength(backoffPolicy.maxAttempts),
      );

      await reconnectCoordinator.dispose();
    });
  });
}

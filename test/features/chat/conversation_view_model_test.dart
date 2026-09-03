import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/local/prompt_database.dart' show PromptDatabase;
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/data/queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_repository.dart';
import 'package:prompt/features/queue/data/queue_send_coordinator.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';

/// Lets Drift's `watch()` timer-scheduled re-query, and any pending
/// microtask chain inside the view model or coordinator, reach a fixed
/// point before the next assertion.
Future<void> _settle({int ticks = 25}) async {
  for (var i = 0; i < ticks; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _settleLive() async {
  await Future<void>.delayed(const Duration(milliseconds: 70));
  await _settle();
}

/// Waits for [done] instead of guessing how long the pipeline needs.
///
/// The view model batches SSE deltas, so a fixed delay is a race against the
/// machine: it passes alone and fails when the suite runs under load. Failing
/// here means the update never arrived, which is a real result rather than a
/// slow one.
Future<void> _settleUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await _settle();
  }
  await _settle();
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

class _CancelledAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

/// A scripted OpenCode REST backend covering the transcript load, and the
/// `prompt_async`/`abort`/`session/status` endpoints the queue coordinator
/// depends on.
class _ScriptedChatBackend {
  String sessionStatusType = 'idle';
  int promptAsyncStatusCode = 204;
  int abortStatusCode = 200;
  bool abortReturnValue = true;

  /// Seeds the REST transcript returned by `GET .../message`, in the raw
  /// OpenCode message-record shape (`{info: {...}, parts: [...]}`).
  List<Map<String, dynamic>> restMessages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> todos = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> diffs = <Map<String, dynamic>>[];
  final List<({String? messageId, Completer<void> gate})> artifactGates = [];
  List<Map<String, dynamic>> messageSpecificDiffs = <Map<String, dynamic>>[];

  int promptAsyncCallCount = 0;
  int abortCallCount = 0;
  final List<String> promptAsyncOrder = <String>[];
  final List<List<Map<String, dynamic>>> promptAsyncParts = [];

  int permissionResponseCallCount = 0;
  int questionReplyCallCount = 0;
  int questionRejectCallCount = 0;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/message')) {
      return http.Response(jsonEncode(restMessages), 200);
    }
    if (path.endsWith('/todo')) {
      return http.Response(jsonEncode(todos), 200);
    }
    if (path.endsWith('/diff')) {
      final messageId = request.url.queryParameters['messageID'];
      final gate = artifactGates.firstWhere(
        (candidate) => candidate.messageId == messageId,
        orElse: () => (messageId: null, gate: Completer<void>()..complete()),
      );
      if (!gate.gate.isCompleted) await gate.gate.future;
      return http.Response(
        jsonEncode(
          messageId == 'message-specific' ? messageSpecificDiffs : diffs,
        ),
        200,
      );
    }
    if (path.endsWith('/prompt_async')) {
      promptAsyncCallCount++;
      promptAsyncParts.add(_promptParts(request.body));
      promptAsyncOrder.add(_promptText(request.body));
      return http.Response('', promptAsyncStatusCode);
    }
    if (path.endsWith('/abort')) {
      abortCallCount++;
      return http.Response(jsonEncode(abortReturnValue), abortStatusCode);
    }
    if (path.contains('/permissions/')) {
      permissionResponseCallCount++;
      return http.Response(jsonEncode(true), 200);
    }
    if (path.endsWith('/reply')) {
      questionReplyCallCount++;
      return http.Response(jsonEncode(true), 200);
    }
    if (path.endsWith('/reject')) {
      questionRejectCallCount++;
      return http.Response(jsonEncode(true), 200);
    }
    if (path == '/session/status') {
      return http.Response(
        jsonEncode({
          'session-1': {'type': sessionStatusType},
        }),
        200,
      );
    }
    return http.Response('', 404);
  }

  String _promptText(String body) {
    final first = _promptParts(body).first;
    return first['text'] as String;
  }

  List<Map<String, dynamic>> _promptParts(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return (decoded['parts'] as List<dynamic>).cast<Map<String, dynamic>>();
  }
}

/// A minimal SSE transport whose byte stream is entirely test-controlled.
class _ScriptedEventClient extends http.BaseClient {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_controller.stream, 200);
  }

  void emit(String type, Map<String, dynamic> properties) {
    final json = jsonEncode({
      'payload': {'type': type, 'properties': properties},
    });
    _controller.add(utf8.encode('data: $json\n\n'));
  }

  @override
  Future<void> close() {
    unawaited(_controller.close());
    return Future<void>.value();
  }
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
  late _ScriptedChatBackend backend;
  late ChatRepository chatRepository;
  late _ScriptedEventClient eventClient;
  late OpenCodeEventService eventService;
  late int repositoryProviderCallCount;
  late int coordinatorProviderCallCount;
  late ConversationViewModel viewModel;

  QueuePromptsRepository buildQueueRepository() {
    return QueuePromptsRepository(DriftQueuePromptsDao(database));
  }

  setUp(() {
    database = PromptDatabase.forTesting(NativeDatabase.memory());
    backend = _ScriptedChatBackend();
    chatRepository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(backend.client)),
      const _StaticPasswordStore(),
    );
    eventClient = _ScriptedEventClient();
    eventService = OpenCodeEventService(OpenCodeTransport(eventClient));
    repositoryProviderCallCount = 0;
    coordinatorProviderCallCount = 0;

    QueuePromptsRepository? sharedRepository;
    QueueSendCoordinator? sharedCoordinator;

    viewModel = ConversationViewModel(
      chatRepository: chatRepository,
      sessionsRepository: SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(backend.client)),
        const _StaticPasswordStore(),
      ),
      queueRepositoryProvider: () async {
        repositoryProviderCallCount++;
        return sharedRepository ??= buildQueueRepository();
      },
      queueCoordinatorProvider: () async {
        coordinatorProviderCallCount++;
        sharedRepository ??= buildQueueRepository();
        return sharedCoordinator ??= QueueSendCoordinator(
          queueRepository: sharedRepository!,
          chatRepository: chatRepository,
          eventService: eventService,
          credentialsStore: const _StaticPasswordStore(),
        );
      },
      attachmentPicker: _CancelledAttachmentPicker(),
    );
  });

  tearDown(() async {
    await viewModel.dispose();
    await eventClient.close();
    await database.close();
  });

  test('never opens the queue database before a conversation is opened', () {
    expect(repositoryProviderCallCount, 0);
    expect(coordinatorProviderCallCount, 0);
  });

  test('open loads the transcript and reports an empty queue for a fresh '
      'session', () async {
    backend.sessionStatusType = 'idle';

    await viewModel.open(profile, session);
    await _settleLive();

    expect(viewModel.messages.value, isA<ConversationReady>());
    expect(viewModel.queue.value, isEmpty);
    expect(repositoryProviderCallCount, 1);
    expect(coordinatorProviderCallCount, 1);
  });

  test('open loads typed session artifacts alongside the transcript', () async {
    backend.sessionStatusType = 'idle';
    backend.todos = [
      {
        'id': 'todo-1',
        'content': 'Review changes',
        'status': 'pending',
        'priority': 'medium',
      },
    ];
    backend.diffs = [
      {
        'file': 'lib/app.dart',
        'before': 'before',
        'after': 'after',
        'additions': 1,
        'deletions': 1,
      },
    ];

    await viewModel.open(profile, session);
    await _settleLive();

    final artifacts = viewModel.artifacts.value as SessionArtifactsReady;
    expect(artifacts.todos.single.content, 'Review changes');
    expect(artifacts.diffs.single.file, 'lib/app.dart');
  });

  test('a live message.updated + message.part.updated event updates the '
      'visible transcript without a manual reload', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settleLive();

    final before = viewModel.messages.value;
    expect(before, isA<ConversationReady>());
    expect((before as ConversationReady).messages, isEmpty);

    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Streamed reply',
      },
    });
    await _settleUntil(() {
      final state = viewModel.messages.value;
      return state is ConversationReady && state.messages.isNotEmpty;
    });

    final after = viewModel.messages.value;
    expect(after, isA<ConversationReady>());
    final messages = (after as ConversationReady).messages;
    expect(messages, hasLength(1));
    expect(messages.single.id, 'msg-1');
    expect(messages.single.text, 'Streamed reply');
    expect(messages.single.role, ChatMessageRole.assistant);
  });

  test('removes a message immediately when SSE reports its removal', () async {
    await viewModel.open(profile, session);
    await _settleLive();

    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Transient',
      },
    });
    await _settleLive();
    eventClient.emit('message.removed', {
      'sessionID': session.id,
      'messageID': 'msg-1',
    });
    await _settleLive();

    expect((viewModel.messages.value as ConversationReady).messages, isEmpty);
  });

  test('removes a part immediately without a REST reload', () async {
    backend.restMessages = [
      {
        'info': {
          'id': 'msg-1',
          'role': 'assistant',
          'time': {'created': 1000},
        },
        'parts': [
          {'id': 'part-1', 'type': 'text', 'text': 'Loaded'},
        ],
      },
    ];
    await viewModel.open(profile, session);
    await _settleLive();

    eventClient.emit('message.part.removed', {
      'sessionID': session.id,
      'messageID': 'msg-1',
      'partID': 'part-1',
    });
    await _settleLive();

    expect(
      (viewModel.messages.value as ConversationReady).messages.single.details,
      isEmpty,
    );
  });

  test('a live update for a new message is added alongside the REST history '
      'instead of discarding it', () async {
    backend.sessionStatusType = 'idle';
    backend.restMessages = [
      {
        'info': {
          'id': 'msg-0',
          'role': 'user',
          'time': {'created': 1000},
        },
        'parts': [
          {'type': 'text', 'text': 'Original REST message'},
        ],
      },
    ];

    await viewModel.open(profile, session);
    await _settleLive();

    final loaded = viewModel.messages.value as ConversationReady;
    expect(loaded.messages.single.text, 'Original REST message');

    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Streamed reply',
      },
    });
    await _settleLive();

    final updated = viewModel.messages.value as ConversationReady;
    expect(updated.messages, hasLength(2));
    expect(updated.messages.first.text, 'Original REST message');
    expect(updated.messages.last.text, 'Streamed reply');
    expect(updated.messages.last.role, ChatMessageRole.assistant);
  });

  test(
    'keeps a loaded tool output when a live status update arrives for it',
    () async {
      backend.sessionStatusType = 'idle';
      backend.restMessages = [
        {
          'info': {
            'id': 'msg-0',
            'role': 'assistant',
            'time': {'created': 1000},
          },
          'parts': [
            {'type': 'text', 'text': 'Reading a file'},
            {
              'id': 'part-tool',
              'type': 'tool',
              'tool': 'read',
              'state': {
                'status': 'completed',
                'input': {'filePath': 'lib/main.dart'},
                'output': 'the loaded tool output',
              },
            },
          ],
        },
      ];

      await viewModel.open(profile, session);
      await _settleLive();

      eventClient.emit('message.part.updated', {
        'part': {
          'id': 'part-tool',
          'messageID': 'msg-0',
          'sessionID': session.id,
          'type': 'tool',
          'tool': 'read',
          'state': {'status': 'completed'},
        },
      });
      await _settleLive();

      final messages = (viewModel.messages.value as ConversationReady).messages;
      final detail = messages.single.details.whereType<ChatToolDetail>().single;
      expect(detail.output, 'the loaded tool output');
    },
  );

  test(
    'keeps a structured subagent payload when a live status omits it',
    () async {
      backend.sessionStatusType = 'idle';
      backend.restMessages = [
        {
          'info': {
            'id': 'msg-0',
            'role': 'assistant',
            'time': {'created': 1000},
          },
          'parts': [
            {
              'id': 'part-task',
              'type': 'tool',
              'tool': 'task',
              'state': {
                'status': 'completed',
                'input': {
                  'description': 'Review changes',
                  'prompt': 'Inspect the diff',
                  'subagent_type': 'reviewer',
                },
                'output':
                    '<task state="completed"><task_result>Looks good</task_result></task>',
              },
            },
          ],
        },
      ];

      await viewModel.open(profile, session);
      await _settleLive();

      eventClient.emit('message.part.updated', {
        'part': {
          'id': 'part-task',
          'messageID': 'msg-0',
          'sessionID': session.id,
          'type': 'tool',
          'tool': 'task',
          'state': {'status': 'completed'},
        },
      });
      await _settleLive();

      final messages = (viewModel.messages.value as ConversationReady).messages;
      final detail = messages.single.details.whereType<ChatToolDetail>().single;
      final task = detail.presentation as ChatTaskPresentation;
      expect(task.description, 'Review changes');
      expect(task.result, 'Looks good');
    },
  );

  test(
    'reconciles the REST transcript when busy execution becomes idle',
    () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
      await _settleLive();
      backend.restMessages = [
        {
          'info': {
            'id': 'msg-task',
            'role': 'assistant',
            'time': {'created': 1000},
          },
          'parts': [
            {
              'id': 'part-reasoning',
              'type': 'reasoning',
              'text': 'I checked the changed files before finishing.',
            },
            {
              'id': 'part-task',
              'type': 'tool',
              'tool': 'task',
              'state': {
                'status': 'completed',
                'input': {'description': 'Review changes'},
                'output': '<task_result>Complete</task_result>',
              },
            },
          ],
        },
      ];

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settleLive();

      final messages = (viewModel.messages.value as ConversationReady).messages;
      final task =
          messages.single.details
                  .whereType<ChatToolDetail>()
                  .single
                  .presentation
              as ChatTaskPresentation;
      final reasoning = messages.single.details
          .whereType<ChatReasoningDetail>()
          .single;
      expect(reasoning.text, 'I checked the changed files before finishing.');
      expect(task.description, 'Review changes');
      expect(task.result, 'Complete');
    },
  );

  test('merges a queued prompt into the one above it', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();

    await viewModel.enqueuePrompt('first');
    await viewModel.enqueuePrompt('second');
    await _settle();

    await viewModel.mergeIntoPrevious(viewModel.queue.value.last.id);
    await _settle();

    expect(viewModel.queue.value, hasLength(1));
    expect(viewModel.queue.value.single.promptText, 'first\n\nsecond');
  });

  test('never overwrites an already-loaded REST message before its own live '
      'text part has arrived', () async {
    backend.sessionStatusType = 'idle';
    backend.restMessages = [
      {
        'info': {
          'id': 'msg-0',
          'role': 'assistant',
          'time': {'created': 1000},
        },
        'parts': [
          {'type': 'text', 'text': 'Already delivered reply'},
        ],
      },
    ];

    await viewModel.open(profile, session);
    await _settle();

    // A metadata-only update for the same message id, with no part
    // event yet, must not blank out its already-loaded text.
    eventClient.emit('message.updated', {
      'info': {'id': 'msg-0', 'sessionID': session.id, 'role': 'assistant'},
    });
    await _settle();

    final messages = (viewModel.messages.value as ConversationReady).messages;
    expect(messages.single.text, 'Already delivered reply');
  });

  test("a live update for a session that is no longer open doesn't leak into "
      'the newly opened session\'s transcript', () async {
    final otherSession = OpenCodeSession(
      id: 'session-2',
      projectId: 'project-1',
      directory: '/workspace/project',
      title: 'Another session',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    backend.sessionStatusType = 'idle';

    await viewModel.open(profile, session);
    await _settle();

    await viewModel.open(profile, otherSession);
    await _settle();

    // Tagged with the previous session's id: must not affect the
    // transcript now open for `otherSession`.
    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Stale text',
      },
    });
    await _settle();

    final state = viewModel.messages.value;
    expect(state, isA<ConversationReady>());
    expect((state as ConversationReady).messages, isEmpty);
  });

  test(
    'opening another session clears the previous transcript immediately',
    () async {
      backend.sessionStatusType = 'idle';
      backend.restMessages = [
        {
          'info': {
            'id': 'old-message',
            'role': 'assistant',
            'time': {'created': 1000},
          },
          'parts': [
            {'type': 'text', 'text': 'Previous transcript'},
          ],
        },
      ];
      await viewModel.open(profile, session);
      await _settle();
      expect(viewModel.messages.value, isA<ConversationReady>());

      final otherSession = OpenCodeSession(
        id: 'session-2',
        projectId: 'project-1',
        directory: '/workspace/project',
        title: 'Another session',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      backend.restMessages = [];
      final opening = viewModel.open(profile, otherSession);

      expect(viewModel.messages.value, isA<ConversationLoading>());
      await opening;
    },
  );

  test('enqueuePrompt durably queues text and the coordinator dispatches it '
      'once idle, never bypassing the queue', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settle();

    await viewModel.enqueuePrompt('hello there');
    await _settle();

    expect(viewModel.queue.value, hasLength(1));
    expect(viewModel.queue.value.single.state, QueuedPromptState.acknowledged);
    expect(backend.promptAsyncCallCount, 1);
    expect(backend.promptAsyncOrder.single, 'hello there');
  });

  test('preserves screenshot media type through queue dispatch', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settle();
    final screenshot = PromptAttachment(
      name: 'Screenshot',
      bytes: Uint8List.fromList([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
    );
    viewModel.attachments.value = [screenshot];

    await viewModel.enqueuePrompt('Review this screenshot');
    await _settle();

    expect(backend.promptAsyncCallCount, 1);
    expect(backend.promptAsyncParts.single[1], {
      'type': 'file',
      'mime': 'image/png',
      'filename': 'Screenshot',
      'url': 'data:image/png;base64,iVBORw0KGgo=',
    });
    expect(screenshot.isReleased, isTrue);
  });

  test('enqueuePrompt queues while busy instead of sending directly', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();

    await viewModel.enqueuePrompt('queued while busy');
    await _settle();

    expect(viewModel.queue.value.single.state, QueuedPromptState.queued);
    expect(backend.promptAsyncCallCount, 0);
    expect(backend.abortCallCount, 0);
  });

  test(
    'releases selected attachment bytes when the conversation leaves',
    () async {
      await viewModel.open(profile, session);
      final attachment = PromptAttachment(
        name: 'notes.txt',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      viewModel.attachments.value = [attachment];

      await viewModel.leave();

      expect(viewModel.attachments.value, isEmpty);
      expect(attachment.isReleased, isTrue);
    },
  );

  test('removeFromQueue removes a queued prompt', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();
    await viewModel.enqueuePrompt('first');
    await _settle();
    final promptId = viewModel.queue.value.single.id;

    await viewModel.removeFromQueue(promptId);
    await _settle();

    expect(viewModel.queue.value, isEmpty);
  });

  test('removeFromQueue reports a rejected removal on queueErrors', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settle();

    final errors = <String>[];
    final subscription = viewModel.queueErrors.listen(errors.add);

    await viewModel.removeFromQueue('does-not-exist');
    await _settle();

    expect(errors, isNotEmpty);
    await subscription.cancel();
  });

  test(
    'sendNow explicitly aborts the active generation before dispatching',
    () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
      await _settle();

      await viewModel.enqueuePrompt('first');
      await viewModel.enqueuePrompt('second');
      await _settle();
      final second = viewModel.queue.value.last;

      await viewModel.sendNow(second.id);
      await _settle();

      expect(backend.abortCallCount, 1);
      expect(backend.promptAsyncCallCount, 0);

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(backend.promptAsyncOrder.first, 'second');
    },
  );

  test('leave deactivates coordination so later SSE events do not '
      'dispatch anything', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();
    await viewModel.enqueuePrompt('first');
    await _settle();

    await viewModel.leave();
    await _settle();

    eventClient.emit('session.idle', {'sessionID': session.id});
    await _settle();

    expect(backend.promptAsyncCallCount, 0);
  });

  group('pendingApproval', () {
    test('surfaces a live permission.updated event with full detail', () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
      await _settle();
      expect(viewModel.pendingApproval.value, isNull);

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

      final detail =
          viewModel.pendingApproval.value as PendingPermissionApproval;
      expect(detail.permissionId, 'perm_1');
      expect(detail.toolType, 'bash');
      expect(detail.title, 'Run a shell command');

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(viewModel.pendingApproval.value, isNull);
    });

    test(
      'respondToPermission submits the response and clears the dock',
      () async {
        backend.sessionStatusType = 'busy';
        await viewModel.open(profile, session);
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

        await viewModel.respondToPermission('perm_1', PermissionResponse.once);
        await _settle();

        expect(backend.permissionResponseCallCount, 1);
        expect(viewModel.pendingApproval.value, isNull);
      },
    );

    test(
      'replyToQuestion and rejectQuestion submit and clear the dock',
      () async {
        backend.sessionStatusType = 'busy';
        await viewModel.open(profile, session);
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
        expect(viewModel.pendingApproval.value, isA<PendingQuestionApproval>());

        await viewModel.replyToQuestion('que_1', [
          ['Postgres'],
        ]);
        await _settle();

        expect(backend.questionReplyCallCount, 1);
        expect(viewModel.pendingApproval.value, isNull);
      },
    );

    test('leave clears the pending approval', () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
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
      expect(viewModel.pendingApproval.value, isNotNull);

      await viewModel.leave();

      expect(viewModel.pendingApproval.value, isNull);
    });
  });

  test('opening a different session tears down coordination for the '
      'previous one', () async {
    final otherSession = OpenCodeSession(
      id: 'session-2',
      projectId: 'project-1',
      directory: '/workspace/project',
      title: 'Another session',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();
    await viewModel.enqueuePrompt('first');
    await _settle();

    await viewModel.open(profile, otherSession);
    await _settle();

    // The queue notifier now reflects the newly opened (empty) session.
    expect(viewModel.queue.value, isEmpty);

    // An SSE event for the first session no longer triggers a dispatch
    // for it, since that session's coordination was torn down.
    eventClient.emit('session.idle', {'sessionID': session.id});
    await _settle();
    expect(backend.promptAsyncCallCount, 0);
  });

  test('newer artifact refresh wins over an older delayed refresh', () async {
    backend.sessionStatusType = 'idle';
    backend.diffs = [
      {'file': 'general-old.dart', 'additions': 1, 'deletions': 0},
    ];
    backend.messageSpecificDiffs = [
      {'file': 'message-new.dart', 'additions': 2, 'deletions': 0},
    ];
    final generalGate = Completer<void>();
    backend.artifactGates.add((messageId: null, gate: generalGate));
    backend.artifactGates.add((
      messageId: 'message-specific',
      gate: Completer<void>()..complete(),
    ));
    await viewModel.open(profile, session);
    await _settle();

    // The initial general request is still waiting; the explicit refresh is
    // newer and completes independently.
    final old = viewModel.reloadArtifacts();
    final newest = viewModel.reloadArtifacts(messageId: 'message-specific');
    await newest;
    expect(
      (viewModel.artifacts.value as SessionArtifactsReady).diffs.single.file,
      'message-new.dart',
    );
    generalGate.complete();
    await old;
    await _settle();
    expect(
      (viewModel.artifacts.value as SessionArtifactsReady).diffs.single.file,
      'message-new.dart',
    );
  });
}

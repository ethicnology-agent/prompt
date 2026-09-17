import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/session_block_reason.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';

OpenCodeEventEnvelope _envelope(
  String type,
  Map<String, dynamic> properties, {
  String? directory,
}) {
  return OpenCodeEventEnvelope(
    directory: directory,
    payload: {'type': type, 'properties': properties},
  );
}

void main() {
  const sessionId = 'ses_1';

  test('explicit gateway error becomes non-dispatchable unknown state', () {
    final event = mapConversationEvent(
      _envelope('session.status', {
        'sessionID': sessionId,
        'status': {'type': 'error'},
      }),
      sessionId: sessionId,
    );
    expect(event, isA<SessionStatusEvent>());
    expect((event as SessionStatusEvent).state, isA<SessionExecutionUnknown>());
  });

  group('message.updated', () {
    test('maps a user message for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': sessionId, 'role': 'user'},
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessageUpdatedEvent>());
      final updated = event as MessageUpdatedEvent;
      expect(updated.messageId, 'msg_1');
      expect(updated.sessionId, sessionId);
      expect(updated.role, ConversationRole.user);
    });

    test('maps an assistant message', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_2', 'sessionID': sessionId, 'role': 'assistant'},
        }),
        sessionId: sessionId,
      );

      expect((event as MessageUpdatedEvent).role, ConversationRole.assistant);
    });

    test('ignores messages belonging to another session', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': 'ses_other', 'role': 'user'},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores an unrecognized role', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': sessionId, 'role': 'system'},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a malformed payload without throwing', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {'info': 'not-a-map'}),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('message.removed', () {
    test('maps a removal for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('message.removed', {
          'sessionID': sessionId,
          'messageID': 'msg_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessageRemovedEvent>());
      expect((event as MessageRemovedEvent).messageId, 'msg_1');
    });

    test('ignores a removal for another session', () {
      final event = mapConversationEvent(
        _envelope('message.removed', {
          'sessionID': 'ses_other',
          'messageID': 'msg_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('message.part.updated', () {
    test('maps a text part', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_1',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'text',
            'text': 'Hello there',
          },
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessagePartUpdatedEvent>());
      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<TextMessagePart>());
      expect((part as TextMessagePart).text, 'Hello there');
      expect(part.id, 'part_1');
      expect(part.messageId, 'msg_1');
    });

    test('maps a reasoning part', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_2',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'reasoning',
            'text': 'thinking...',
          },
        }),
        sessionId: sessionId,
      );

      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<ReasoningMessagePart>());
      expect((part as ReasoningMessagePart).text, 'thinking...');
    });

    test('maps a tool part with a safe live summary', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_3',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'tool',
            'tool': 'bash',
            'callID': 'call_1',
            'state': {
              'status': 'running',
              'input': {'command': 'ls'},
            },
          },
        }),
        sessionId: sessionId,
      );

      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<ToolMessagePart>());
      final tool = part as ToolMessagePart;
      expect(tool.tool, 'bash');
      expect(tool.status, ToolPartStatus.running);
      expect(tool.summary, 'ls');
    });

    test('keeps a subagent task description while it is running', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_task',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'tool',
            'tool': 'task',
            'state': {
              'status': 'running',
              'input': {'description': 'Review the authentication flow'},
            },
          },
        }),
        sessionId: sessionId,
      );

      final tool = (event as MessagePartUpdatedEvent).part as ToolMessagePart;
      expect(tool.summary, 'Review the authentication flow');
    });

    test('maps every documented tool status', () {
      for (final entry in const {
        'pending': ToolPartStatus.pending,
        'running': ToolPartStatus.running,
        'completed': ToolPartStatus.completed,
        'error': ToolPartStatus.error,
      }.entries) {
        final event = mapConversationEvent(
          _envelope('message.part.updated', {
            'part': {
              'id': 'part_x',
              'sessionID': sessionId,
              'messageID': 'msg_1',
              'type': 'tool',
              'tool': 'bash',
              'state': {'status': entry.key},
            },
          }),
          sessionId: sessionId,
        );

        final part = (event as MessagePartUpdatedEvent).part as ToolMessagePart;
        expect(part.status, entry.value);
      }
    });

    test('preserves identity of an unmodeled part type', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_4',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'step-start',
          },
        }),
        sessionId: sessionId,
      );

      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<OtherMessagePart>());
      expect((part as OtherMessagePart).partType, 'step-start');
    });

    test('ignores a part belonging to another session', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_1',
            'sessionID': 'ses_other',
            'messageID': 'msg_1',
            'type': 'text',
            'text': 'hi',
          },
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a tool part with an unrecognized status', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_3',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'tool',
            'tool': 'bash',
            'state': {'status': 'unknown-status'},
          },
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('message.part.removed', () {
    test('maps a removal for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('message.part.removed', {
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'partID': 'part_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessagePartRemovedEvent>());
      final removed = event as MessagePartRemovedEvent;
      expect(removed.messageId, 'msg_1');
      expect(removed.partId, 'part_1');
    });

    test('ignores a removal for another session', () {
      final event = mapConversationEvent(
        _envelope('message.part.removed', {
          'sessionID': 'ses_other',
          'messageID': 'msg_1',
          'partID': 'part_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('session.status', () {
    test('maps a busy status', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {'type': 'busy'},
        }),
        sessionId: sessionId,
      );

      expect(event, isA<SessionStatusEvent>());
      expect((event as SessionStatusEvent).state, isA<SessionBusy>());
    });

    test('maps an idle status', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {'type': 'idle'},
        }),
        sessionId: sessionId,
      );

      expect((event as SessionStatusEvent).state, isA<SessionIdle>());
    });

    test('maps a retry status with attempt metadata', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {
            'type': 'retry',
            'attempt': 2,
            'message': 'rate limited',
            'next': 1700000000000,
          },
        }),
        sessionId: sessionId,
      );

      final state = (event as SessionStatusEvent).state as SessionRetrying;
      expect(state.attempt, 2);
      expect(state.message, 'rate limited');
      expect(state.nextAttemptAtMillis, 1700000000000);
    });

    test('ignores a status for another session', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': 'ses_other',
          'status': {'type': 'busy'},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('session.idle', () {
    test('maps an idle event for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {'sessionID': sessionId}),
        sessionId: sessionId,
      );

      expect(event, isA<SessionIdleEvent>());
      expect((event as SessionIdleEvent).sessionId, sessionId);
    });

    test('ignores an idle event for another session', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {'sessionID': 'ses_other'}),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('permission.updated', () {
    test('maps a tool-call permission as SessionBlockReason.permission', () {
      final event = mapConversationEvent(
        _envelope('permission.updated', {
          'id': 'perm_1',
          'type': 'bash',
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'title': 'Run rm -rf /tmp/build',
          'metadata': <String, dynamic>{},
          'time': {'created': 1700000000000},
        }),
        sessionId: sessionId,
      );

      expect(event, isA<SessionBlockedEvent>());
      final blocked = event as SessionBlockedEvent;
      expect(blocked.sessionId, sessionId);
      expect(blocked.reason, SessionBlockReason.permission);
    });

    test('maps the built-in question permission as '
        'SessionBlockReason.question', () {
      final event = mapConversationEvent(
        _envelope('permission.updated', {
          'id': 'perm_2',
          'type': 'question',
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'title': 'Which database should I use?',
          'metadata': <String, dynamic>{},
          'time': {'created': 1700000000000},
        }),
        sessionId: sessionId,
      );

      expect(
        (event as SessionBlockedEvent).reason,
        SessionBlockReason.question,
      );
    });

    test('ignores a permission for another session', () {
      final event = mapConversationEvent(
        _envelope('permission.updated', {
          'id': 'perm_1',
          'type': 'bash',
          'sessionID': 'ses_other',
          'messageID': 'msg_1',
          'title': 'Run something',
          'metadata': <String, dynamic>{},
          'time': {'created': 1700000000000},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('a sensitive edit permission never carries pattern or metadata, only '
        'title', () {
      final event = mapConversationEvent(
        _envelope('permission.updated', {
          'id': 'perm_1',
          'type': 'edit',
          'pattern': '/home/user/.ssh/*',
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'title': 'Edit ~/.ssh/authorized_keys',
          'metadata': {'secret': 'sensitive-detail'},
          'time': {'created': 1700000000000},
        }),
        sessionId: sessionId,
      );

      // `SessionBlockedEvent.reason` never carries sensitive detail;
      // `detail` carries only `id`/`type`/`title` — never `pattern` or
      // `metadata`, which have no field to reach through at all.
      final blocked = event as SessionBlockedEvent;
      expect(blocked.sessionId, sessionId);
      expect(blocked.reason, SessionBlockReason.permission);
      final detail = blocked.detail as PendingPermissionApproval;
      expect(detail.permissionId, 'perm_1');
      expect(detail.toolType, 'edit');
      expect(detail.title, 'Edit ~/.ssh/authorized_keys');
    });

    test('carries the full permission detail for the approval UI', () {
      final event = mapConversationEvent(
        _envelope('permission.updated', {
          'id': 'perm_1',
          'type': 'bash',
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'title': 'Run rm -rf /tmp/build',
          'metadata': <String, dynamic>{},
          'time': {'created': 1700000000000},
        }),
        sessionId: sessionId,
      );

      final detail =
          (event as SessionBlockedEvent).detail as PendingPermissionApproval;
      expect(detail.sessionId, sessionId);
      expect(detail.permissionId, 'perm_1');
      expect(detail.toolType, 'bash');
      expect(detail.title, 'Run rm -rf /tmp/build');
    });

    test('maps a permission missing id or title with no detail', () {
      final event = mapConversationEvent(
        _envelope('permission.updated', {
          'type': 'bash',
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'metadata': <String, dynamic>{},
          'time': {'created': 1700000000000},
        }),
        sessionId: sessionId,
      );

      final blocked = event as SessionBlockedEvent;
      expect(blocked.reason, SessionBlockReason.permission);
      expect(blocked.detail, isNull);
    });
  });

  group('question.asked', () {
    test('maps a single-choice question with full detail', () {
      final event = mapConversationEvent(
        _envelope('question.asked', {
          'id': 'que_1',
          'sessionID': sessionId,
          'questions': [
            {
              'question': 'Which database should I use?',
              'header': 'Database choice',
              'options': [
                {'label': 'Postgres', 'description': 'Relational, robust'},
                {'label': 'SQLite', 'description': 'Embedded, simple'},
              ],
            },
          ],
        }),
        sessionId: sessionId,
      );

      expect(event, isA<SessionBlockedEvent>());
      final blocked = event as SessionBlockedEvent;
      expect(blocked.sessionId, sessionId);
      expect(blocked.reason, SessionBlockReason.question);
      final detail = blocked.detail as PendingQuestionApproval;
      expect(detail.requestId, 'que_1');
      expect(detail.questions, hasLength(1));
      final question = detail.questions.single;
      expect(question.question, 'Which database should I use?');
      expect(question.header, 'Database choice');
      expect(question.multiple, isFalse);
      expect(question.allowsCustomAnswer, isTrue);
      expect(question.options, hasLength(2));
      expect(question.options.first.label, 'Postgres');
      expect(question.options.first.description, 'Relational, robust');
    });

    test('maps multiple/custom flags and multiple questions', () {
      final event = mapConversationEvent(
        _envelope('question.asked', {
          'id': 'que_2',
          'sessionID': sessionId,
          'questions': [
            {
              'question': 'Which languages should I support?',
              'header': 'Languages',
              'options': [
                {'label': 'Dart', 'description': 'This project'},
                {'label': 'Rust', 'description': 'Native voice engine'},
              ],
              'multiple': true,
              'custom': false,
            },
            {
              'question': 'Anything else?',
              'header': 'Other',
              'options': <Map<String, dynamic>>[],
            },
          ],
        }),
        sessionId: sessionId,
      );

      final detail =
          (event as SessionBlockedEvent).detail as PendingQuestionApproval;
      expect(detail.questions, hasLength(2));
      expect(detail.questions[0].multiple, isTrue);
      expect(detail.questions[0].allowsCustomAnswer, isFalse);
      expect(detail.questions[1].options, isEmpty);
      // Absent `custom` defaults to true, matching OpenCode's own default.
      expect(detail.questions[1].allowsCustomAnswer, isTrue);
    });

    test('ignores a question request for another session', () {
      final event = mapConversationEvent(
        _envelope('question.asked', {
          'id': 'que_1',
          'sessionID': 'ses_other',
          'questions': [
            {
              'question': 'Which database should I use?',
              'header': 'Database choice',
              'options': <Map<String, dynamic>>[],
            },
          ],
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a request with no questions', () {
      final event = mapConversationEvent(
        _envelope('question.asked', {
          'id': 'que_1',
          'sessionID': sessionId,
          'questions': <Map<String, dynamic>>[],
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a malformed question payload without throwing', () {
      final event = mapConversationEvent(
        _envelope('question.asked', {
          'id': 'que_1',
          'sessionID': sessionId,
          'questions': [
            {'question': 'Missing header and options'},
          ],
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a malformed option within a question', () {
      final event = mapConversationEvent(
        _envelope('question.asked', {
          'id': 'que_1',
          'sessionID': sessionId,
          'questions': [
            {
              'question': 'Which one?',
              'header': 'Pick one',
              'options': [
                {'label': 'Only label, no description'},
              ],
            },
          ],
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('unrelated and unknown events', () {
    test('ignores unmodeled event types', () {
      for (final type in const [
        'session.error',
        'session.compacted',
        'file.edited',
        'permission.replied',
        'question.replied',
        'question.rejected',
        'installation.updated',
        'todo.updated',
        'server.connected',
        'server.instance.disposed',
        'lsp.updated',
        'something.unexpected',
      ]) {
        final event = mapConversationEvent(
          _envelope(type, {'sessionID': sessionId}),
          sessionId: sessionId,
        );

        expect(event, isNull, reason: 'expected $type to be ignored');
      }
    });

    test('ignores events carrying no type', () {
      final event = mapConversationEvent(
        OpenCodeEventEnvelope(directory: null, payload: {'properties': {}}),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores events for a different directory', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {
          'sessionID': sessionId,
        }, directory: '/workspace/other'),
        sessionId: sessionId,
        directory: '/workspace/mine',
      );

      expect(event, isNull);
    });

    test('accepts a matching directory', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {
          'sessionID': sessionId,
        }, directory: '/workspace/mine'),
        sessionId: sessionId,
        directory: '/workspace/mine',
      );

      expect(event, isA<SessionIdleEvent>());
    });

    test('accepts an event without a directory when one is required', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {'sessionID': sessionId}),
        sessionId: sessionId,
        directory: '/workspace/mine',
      );

      expect(event, isA<SessionIdleEvent>());
    });
  });
}

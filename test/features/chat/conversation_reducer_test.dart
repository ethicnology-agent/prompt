import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';
import 'package:prompt/features/chat/domain/conversation_state.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/session_block_reason.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';

OpenCodeEventEnvelope _envelope(String type, Map<String, dynamic> properties) {
  return OpenCodeEventEnvelope(
    directory: null,
    payload: {'type': type, 'properties': properties},
  );
}

void main() {
  const sessionId = 'ses_1';

  test(
    'permission reply clears only matching detail and preserves execution block',
    () {
      const state = ConversationState(
        sessionStates: {sessionId: SessionBusy()},
        sessionBlocks: {sessionId: SessionBlockReason.permission},
        pendingApprovals: {
          sessionId: PendingPermissionApproval(
            sessionId: sessionId,
            permissionId: 'request',
            toolType: 'bash',
            title: 'Approve',
          ),
        },
      );
      final event = mapConversationEvent(
        _envelope('permission.replied', {
          'sessionID': sessionId,
          'requestID': 'request',
        }),
        sessionId: sessionId,
      );
      expect(event, isNotNull);
      expect(event, isA<PermissionRepliedEvent>());
      final next = reduceConversationEvent(state, event!);
      expect(next.pendingApprovals, isEmpty);
      expect(next.sessionBlocks, same(state.sessionBlocks));
      expect(next.sessionStates, same(state.sessionStates));
      final unrelated = mapConversationEvent(
        _envelope('permission.replied', {
          'sessionID': sessionId,
          'requestID': 'other',
        }),
        sessionId: sessionId,
      )!;
      expect(reduceConversationEvent(state, unrelated), same(state));
      final question = state.copyWith(
        pendingApprovals: const {
          sessionId: PendingQuestionApproval(
            sessionId: sessionId,
            requestId: 'request',
            questions: [],
          ),
        },
      );
      expect(reduceConversationEvent(question, event), same(question));
      expect(
        mapConversationEvent(
          _envelope('permission.replied', {
            'sessionID': 'wrong',
            'requestID': 'request',
          }),
          sessionId: sessionId,
        ),
        isNull,
      );
      expect(
        mapConversationEvent(
          _envelope('permission.replied', {
            'sessionID': sessionId,
            'requestID': '',
          }),
          sessionId: sessionId,
        ),
        isNull,
      );
    },
  );

  group('message.updated', () {
    test('creates a new message with no parts', () {
      const state = ConversationState();

      final next = reduceConversationEvent(
        state,
        const MessageUpdatedEvent(
          sessionId: sessionId,
          messageId: 'msg_1',
          role: ConversationRole.user,
        ),
      );

      expect(next.messages, hasLength(1));
      final message = next.messages['msg_1']!;
      expect(message.sessionId, sessionId);
      expect(message.role, ConversationRole.user);
      expect(message.parts, isEmpty);
    });

    test('preserves existing parts when the same message updates again', () {
      final withPart = reduceConversationEvent(
        const ConversationState(),
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'Hello',
          ),
        ),
      );

      final next = reduceConversationEvent(
        withPart,
        const MessageUpdatedEvent(
          sessionId: sessionId,
          messageId: 'msg_1',
          role: ConversationRole.assistant,
        ),
      );

      final message = next.messages['msg_1']!;
      expect(message.role, ConversationRole.assistant);
      expect(message.parts, hasLength(1));
      expect((message.parts.single as TextMessagePart).text, 'Hello');
    });

    test('does not disturb other messages', () {
      final state = reduceConversationEvent(
        const ConversationState(),
        const MessageUpdatedEvent(
          sessionId: sessionId,
          messageId: 'msg_1',
          role: ConversationRole.user,
        ),
      );

      final next = reduceConversationEvent(
        state,
        const MessageUpdatedEvent(
          sessionId: sessionId,
          messageId: 'msg_2',
          role: ConversationRole.assistant,
        ),
      );

      expect(next.messages.keys, containsAllInOrder(['msg_1', 'msg_2']));
    });
  });

  group('message.removed', () {
    test('removes a message and its parts', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const MessageUpdatedEvent(
          sessionId: sessionId,
          messageId: 'msg_1',
          role: ConversationRole.user,
        ),
      );
      state = reduceConversationEvent(
        state,
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'Hello',
          ),
        ),
      );

      final next = reduceConversationEvent(
        state,
        const MessageRemovedEvent(sessionId: sessionId, messageId: 'msg_1'),
      );

      expect(next.messages, isEmpty);
    });

    test('is a no-op for an unknown message id', () {
      const state = ConversationState();

      final next = reduceConversationEvent(
        state,
        const MessageRemovedEvent(sessionId: sessionId, messageId: 'missing'),
      );

      expect(next.messages, isEmpty);
      expect(next, same(state));
    });
  });

  group('message.part.updated', () {
    test('creates a placeholder message when the part arrives first', () {
      final next = reduceConversationEvent(
        const ConversationState(),
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'Hello',
          ),
        ),
      );

      final message = next.messages['msg_1']!;
      expect(message.role, ConversationRole.unknown);
      expect(message.sessionId, sessionId);
      expect(message.parts, hasLength(1));
    });

    test('appends a new part while preserving prior part order', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'first',
          ),
        ),
      );
      state = reduceConversationEvent(
        state,
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const ReasoningMessagePart(
            id: 'part_2',
            messageId: 'msg_1',
            text: 'thinking',
          ),
        ),
      );

      final parts = state.messages['msg_1']!.parts;
      expect(parts, hasLength(2));
      expect(parts[0].id, 'part_1');
      expect(parts[1].id, 'part_2');
    });

    test('replaces a part snapshot in place without moving its position', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'first',
          ),
        ),
      );
      state = reduceConversationEvent(
        state,
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const ReasoningMessagePart(
            id: 'part_2',
            messageId: 'msg_1',
            text: 'thinking',
          ),
        ),
      );

      final next = reduceConversationEvent(
        state,
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'first, revised entirely',
          ),
        ),
      );

      final parts = next.messages['msg_1']!.parts;
      expect(parts, hasLength(2));
      expect(parts[0].id, 'part_1');
      expect((parts[0] as TextMessagePart).text, 'first, revised entirely');
      expect(parts[1].id, 'part_2');
    });

    test('a later tool status snapshot fully replaces the earlier one', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const ToolMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            tool: 'bash',
            status: ToolPartStatus.running,
          ),
        ),
      );

      state = reduceConversationEvent(
        state,
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const ToolMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            tool: 'bash',
            status: ToolPartStatus.completed,
          ),
        ),
      );

      final part = state.messages['msg_1']!.parts.single as ToolMessagePart;
      expect(part.status, ToolPartStatus.completed);
    });
  });

  group('message.part.removed', () {
    test('removes only the targeted part', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const TextMessagePart(
            id: 'part_1',
            messageId: 'msg_1',
            text: 'first',
          ),
        ),
      );
      state = reduceConversationEvent(
        state,
        MessagePartUpdatedEvent(
          sessionId: sessionId,
          part: const ReasoningMessagePart(
            id: 'part_2',
            messageId: 'msg_1',
            text: 'thinking',
          ),
        ),
      );

      final next = reduceConversationEvent(
        state,
        const MessagePartRemovedEvent(
          sessionId: sessionId,
          messageId: 'msg_1',
          partId: 'part_1',
        ),
      );

      final parts = next.messages['msg_1']!.parts;
      expect(parts, hasLength(1));
      expect(parts.single.id, 'part_2');
    });

    test('is a no-op when the message is unknown', () {
      const state = ConversationState();

      final next = reduceConversationEvent(
        state,
        const MessagePartRemovedEvent(
          sessionId: sessionId,
          messageId: 'missing',
          partId: 'part_1',
        ),
      );

      expect(next, same(state));
    });
  });

  group('session.status and session.idle', () {
    test('tracks busy, retrying, then idle in sequence', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionStatusEvent(sessionId: sessionId, state: SessionBusy()),
      );
      expect(state.sessionStates[sessionId], isA<SessionBusy>());

      state = reduceConversationEvent(
        state,
        const SessionStatusEvent(
          sessionId: sessionId,
          state: SessionRetrying(
            attempt: 1,
            nextAttemptAtMillis: 1700000000000,
          ),
        ),
      );
      final retrying = state.sessionStates[sessionId] as SessionRetrying;
      expect(retrying.attempt, 1);
      expect(retrying.nextAttemptAtMillis, 1700000000000);

      state = reduceConversationEvent(
        state,
        const SessionIdleEvent(sessionId: sessionId),
      );
      expect(state.sessionStates[sessionId], isA<SessionIdle>());
    });

    test('tracks independent sessions separately', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionStatusEvent(sessionId: 'ses_a', state: SessionBusy()),
      );
      state = reduceConversationEvent(
        state,
        const SessionStatusEvent(sessionId: 'ses_b', state: SessionIdle()),
      );

      expect(state.sessionStates['ses_a'], isA<SessionBusy>());
      expect(state.sessionStates['ses_b'], isA<SessionIdle>());
    });
  });

  group('permission.updated', () {
    test('records a pending permission for the session', () {
      final state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.permission,
        ),
      );

      expect(state.sessionBlocks[sessionId], SessionBlockReason.permission);
    });

    test('a later permission overwrites the recorded reason', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.permission,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.question,
        ),
      );

      expect(state.sessionBlocks[sessionId], SessionBlockReason.question);
    });

    test('tracks independent sessions separately', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: 'ses_a',
          reason: SessionBlockReason.permission,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionBlockedEvent(
          sessionId: 'ses_b',
          reason: SessionBlockReason.question,
        ),
      );

      expect(state.sessionBlocks['ses_a'], SessionBlockReason.permission);
      expect(state.sessionBlocks['ses_b'], SessionBlockReason.question);
    });

    test('a session.status event clears the pending block', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.permission,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionStatusEvent(sessionId: sessionId, state: SessionBusy()),
      );

      expect(state.sessionBlocks.containsKey(sessionId), isFalse);
      // Clearing the block never disturbs the execution state it carried.
      expect(state.sessionStates[sessionId], isA<SessionBusy>());
    });

    test('a session.idle event clears the pending block', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.question,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionIdleEvent(sessionId: sessionId),
      );

      expect(state.sessionBlocks.containsKey(sessionId), isFalse);
    });

    test('clearing one session leaves another session blocked', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: 'ses_a',
          reason: SessionBlockReason.permission,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionBlockedEvent(
          sessionId: 'ses_b',
          reason: SessionBlockReason.question,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionIdleEvent(sessionId: 'ses_a'),
      );

      expect(state.sessionBlocks.containsKey('ses_a'), isFalse);
      expect(state.sessionBlocks['ses_b'], SessionBlockReason.question);
    });
  });

  group('pending approval detail', () {
    const detail = PendingPermissionApproval(
      sessionId: sessionId,
      permissionId: 'perm_1',
      toolType: 'bash',
      title: 'Run a shell command',
    );

    test('records the detail alongside the coarse block reason', () {
      final state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.permission,
          detail: detail,
        ),
      );

      expect(state.pendingApprovals[sessionId], same(detail));
      expect(state.sessionBlocks[sessionId], SessionBlockReason.permission);
    });

    test('a session.status event clears the detail with the block', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.permission,
          detail: detail,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionStatusEvent(sessionId: sessionId, state: SessionBusy()),
      );

      expect(state.pendingApprovals.containsKey(sessionId), isFalse);
      expect(state.sessionBlocks.containsKey(sessionId), isFalse);
    });

    test('a session.idle event clears the detail with the block', () {
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.question,
          detail: detail,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionIdleEvent(sessionId: sessionId),
      );

      expect(state.pendingApprovals.containsKey(sessionId), isFalse);
    });

    test(
      'a block constructed without detail leaves any prior detail alone',
      () {
        var state = reduceConversationEvent(
          const ConversationState(),
          const SessionBlockedEvent(
            sessionId: sessionId,
            reason: SessionBlockReason.permission,
            detail: detail,
          ),
        );
        state = reduceConversationEvent(
          state,
          const SessionBlockedEvent(
            sessionId: sessionId,
            reason: SessionBlockReason.permission,
          ),
        );

        expect(state.pendingApprovals[sessionId], same(detail));
      },
    );

    test('clearPendingApproval removes only the detail, keeping the block', () {
      final blocked = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: sessionId,
          reason: SessionBlockReason.permission,
          detail: detail,
        ),
      );

      final cleared = clearPendingApproval(blocked, sessionId);

      expect(cleared.pendingApprovals.containsKey(sessionId), isFalse);
      expect(cleared.sessionBlocks[sessionId], SessionBlockReason.permission);
    });

    test('clearPendingApproval is a no-op, returning the same state, when '
        'nothing is pending', () {
      const state = ConversationState();

      final cleared = clearPendingApproval(state, sessionId);

      expect(identical(cleared, state), isTrue);
    });

    test('tracks independent sessions separately', () {
      const detailA = PendingPermissionApproval(
        sessionId: 'ses_a',
        permissionId: 'perm_a',
        toolType: 'bash',
        title: 'Run a shell command',
      );
      const detailB = PendingPermissionApproval(
        sessionId: 'ses_b',
        permissionId: 'perm_b',
        toolType: 'edit',
        title: 'Edit a file',
      );
      var state = reduceConversationEvent(
        const ConversationState(),
        const SessionBlockedEvent(
          sessionId: 'ses_a',
          reason: SessionBlockReason.permission,
          detail: detailA,
        ),
      );
      state = reduceConversationEvent(
        state,
        const SessionBlockedEvent(
          sessionId: 'ses_b',
          reason: SessionBlockReason.permission,
          detail: detailB,
        ),
      );

      expect(state.pendingApprovals['ses_a'], same(detailA));
      expect(state.pendingApprovals['ses_b'], same(detailB));

      final cleared = clearPendingApproval(state, 'ses_a');
      expect(cleared.pendingApprovals.containsKey('ses_a'), isFalse);
      expect(cleared.pendingApprovals['ses_b'], same(detailB));
    });
  });

  group('end-to-end mapping and reduction', () {
    test('folds a realistic event sequence, ignoring unrelated events', () {
      final envelopes = <OpenCodeEventEnvelope>[
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': sessionId, 'role': 'user'},
        }),
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_1',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'text',
            'text': 'What is 2+2?',
          },
        }),
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {'type': 'busy'},
        }),
        // Unrelated session: must not affect state.
        _envelope('message.updated', {
          'info': {'id': 'msg_other', 'sessionID': 'ses_other', 'role': 'user'},
        }),
        // Unknown event type: must be ignored.
        _envelope('session.error', {'sessionID': sessionId}),
        _envelope('message.updated', {
          'info': {'id': 'msg_2', 'sessionID': sessionId, 'role': 'assistant'},
        }),
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_2',
            'sessionID': sessionId,
            'messageID': 'msg_2',
            'type': 'tool',
            'tool': 'calculator',
            'state': {'status': 'running'},
          },
        }),
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_2',
            'sessionID': sessionId,
            'messageID': 'msg_2',
            'type': 'tool',
            'tool': 'calculator',
            'state': {'status': 'completed'},
          },
        }),
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_3',
            'sessionID': sessionId,
            'messageID': 'msg_2',
            'type': 'text',
            'text': '4',
          },
        }),
        _envelope('session.idle', {'sessionID': sessionId}),
      ];

      var state = const ConversationState();
      for (final envelope in envelopes) {
        final event = mapConversationEvent(envelope, sessionId: sessionId);
        if (event == null) {
          continue;
        }
        state = reduceConversationEvent(state, event);
      }

      expect(state.messages.keys, containsAllInOrder(['msg_1', 'msg_2']));
      expect(state.messages.containsKey('msg_other'), isFalse);

      final userMessage = state.messages['msg_1']!;
      expect(userMessage.role, ConversationRole.user);
      expect(
        (userMessage.parts.single as TextMessagePart).text,
        'What is 2+2?',
      );

      final assistantMessage = state.messages['msg_2']!;
      expect(assistantMessage.role, ConversationRole.assistant);
      expect(assistantMessage.parts, hasLength(2));
      final tool = assistantMessage.parts[0] as ToolMessagePart;
      expect(tool.status, ToolPartStatus.completed);
      final text = assistantMessage.parts[1] as TextMessagePart;
      expect(text.text, '4');

      expect(state.sessionStates[sessionId], isA<SessionIdle>());
    });
  });
}

/// Pure reducer that folds [ConversationEvent]s, already mapped by
/// `conversation_event.dart`, into a [ConversationState]. This file performs
/// no I/O, no logging, and no OpenCode/HTTP/Drift access; it is safe to unit
/// test with plain Dart values.
library;

import 'conversation_event.dart';
import 'conversation_message.dart';
import 'pending_approval.dart';
import 'session_block_reason.dart';
import 'session_execution_state.dart';

/// Immutable snapshot of a live conversation: its messages, in first-seen
/// order, the execution state of every session referenced so far, and
/// which of those sessions currently have a pending permission or question
/// blocking their queue.
class ConversationState {
  const ConversationState({
    this.messages = const <String, ConversationMessage>{},
    this.sessionStates = const <String, SessionExecutionState>{},
    this.sessionBlocks = const <String, SessionBlockReason>{},
    this.pendingApprovals = const <String, PendingApproval>{},
  });

  /// Messages keyed by message id, preserving the order in which each
  /// message was first observed.
  final Map<String, ConversationMessage> messages;

  /// Execution state keyed by session id.
  final Map<String, SessionExecutionState> sessionStates;

  /// Sessions with a pending permission or question, keyed by session id.
  /// A session present here is not present because it has been resolved
  /// (`permission.replied` only retires presentation); an entry is only removed
  /// when a fresh `session.status`/`session.idle` event authoritatively
  /// confirms the session moved past it.
  final Map<String, SessionBlockReason> sessionBlocks;

  /// The full pending-approval detail behind [sessionBlocks], keyed by
  /// session id, for the sessions [SessionBlockedEvent] carried a
  /// [PendingApproval] for. Cleared the same way [sessionBlocks] is, and
  /// also clearable on its own — without disturbing [sessionBlocks] — by
  /// [clearPendingApproval], once a reply/reject to OpenCode succeeds. See
  /// `pending_approval.dart` for why this must never be logged or
  /// persisted.
  final Map<String, PendingApproval> pendingApprovals;

  /// Messages in first-seen order.
  List<ConversationMessage> get orderedMessages =>
      List.unmodifiable(messages.values);

  ConversationState copyWith({
    Map<String, ConversationMessage>? messages,
    Map<String, SessionExecutionState>? sessionStates,
    Map<String, SessionBlockReason>? sessionBlocks,
    Map<String, PendingApproval>? pendingApprovals,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      sessionStates: sessionStates ?? this.sessionStates,
      sessionBlocks: sessionBlocks ?? this.sessionBlocks,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    );
  }
}

/// Folds [event] onto [state] and returns the resulting state. [state] is
/// never mutated in place.
ConversationState reduceConversationEvent(
  ConversationState state,
  ConversationEvent event,
) {
  switch (event) {
    case MessageUpdatedEvent():
      return _reduceMessageUpdated(state, event);
    case MessageRemovedEvent():
      return _reduceMessageRemoved(state, event);
    case MessagePartUpdatedEvent():
      return _reduceMessagePartUpdated(state, event);
    case MessagePartRemovedEvent():
      return _reduceMessagePartRemoved(state, event);
    case SessionStatusEvent():
      return _reduceSessionStatus(state, event);
    case SessionIdleEvent():
      return _reduceSessionIdle(state, event);
    case SessionBlockedEvent():
      return _reduceSessionBlocked(state, event);
    case PermissionRepliedEvent():
      final approval = state.pendingApprovals[event.sessionId];
      if (approval is! PendingPermissionApproval ||
          approval.sessionId != event.sessionId ||
          approval.permissionId != event.requestId) {
        return state;
      }
      return clearPendingApproval(state, event.sessionId);
  }
}

ConversationState _reduceMessageUpdated(
  ConversationState state,
  MessageUpdatedEvent event,
) {
  final existing = state.messages[event.messageId];
  final messages = Map<String, ConversationMessage>.of(state.messages);
  messages[event.messageId] = ConversationMessage(
    id: event.messageId,
    sessionId: event.sessionId,
    role: event.role,
    parts: existing?.parts ?? const <MessagePart>[],
  );
  return state.copyWith(messages: messages);
}

ConversationState _reduceMessageRemoved(
  ConversationState state,
  MessageRemovedEvent event,
) {
  if (!state.messages.containsKey(event.messageId)) {
    return state;
  }
  final messages = Map<String, ConversationMessage>.of(state.messages)
    ..remove(event.messageId);
  return state.copyWith(messages: messages);
}

ConversationState _reduceMessagePartUpdated(
  ConversationState state,
  MessagePartUpdatedEvent event,
) {
  final part = event.part;
  final existing = state.messages[part.messageId];
  final base =
      existing ??
      ConversationMessage(
        id: part.messageId,
        sessionId: event.sessionId,
        role: ConversationRole.unknown,
      );
  final messages = Map<String, ConversationMessage>.of(state.messages);
  messages[part.messageId] = base.copyWith(
    parts: _upsertPart(base.parts, part),
  );
  return state.copyWith(messages: messages);
}

List<MessagePart> _upsertPart(List<MessagePart> parts, MessagePart part) {
  final index = parts.indexWhere((existing) => existing.id == part.id);
  if (index == -1) {
    return List<MessagePart>.of(parts)..add(part);
  }
  final next = List<MessagePart>.of(parts);
  next[index] = part;
  return next;
}

ConversationState _reduceMessagePartRemoved(
  ConversationState state,
  MessagePartRemovedEvent event,
) {
  final existing = state.messages[event.messageId];
  if (existing == null) {
    return state;
  }
  final parts = existing.parts
      .where((part) => part.id != event.partId)
      .toList(growable: false);
  if (parts.length == existing.parts.length) {
    return state;
  }
  final messages = Map<String, ConversationMessage>.of(state.messages);
  messages[event.messageId] = existing.copyWith(parts: parts);
  return state.copyWith(messages: messages);
}

ConversationState _reduceSessionStatus(
  ConversationState state,
  SessionStatusEvent event,
) {
  final sessionStates = Map<String, SessionExecutionState>.of(
    state.sessionStates,
  );
  sessionStates[event.sessionId] = event.state;
  return state.copyWith(
    sessionStates: sessionStates,
    sessionBlocks: _clearSessionBlock(state, event.sessionId),
    pendingApprovals: _clearPendingApproval(state, event.sessionId),
  );
}

ConversationState _reduceSessionIdle(
  ConversationState state,
  SessionIdleEvent event,
) {
  final sessionStates = Map<String, SessionExecutionState>.of(
    state.sessionStates,
  );
  sessionStates[event.sessionId] = const SessionIdle();
  return state.copyWith(
    sessionStates: sessionStates,
    sessionBlocks: _clearSessionBlock(state, event.sessionId),
    pendingApprovals: _clearPendingApproval(state, event.sessionId),
  );
}

ConversationState _reduceSessionBlocked(
  ConversationState state,
  SessionBlockedEvent event,
) {
  final sessionBlocks = Map<String, SessionBlockReason>.of(state.sessionBlocks);
  sessionBlocks[event.sessionId] = event.reason;
  final detail = event.detail;
  if (detail == null) {
    return state.copyWith(sessionBlocks: sessionBlocks);
  }
  final pendingApprovals = Map<String, PendingApproval>.of(
    state.pendingApprovals,
  );
  pendingApprovals[event.sessionId] = detail;
  return state.copyWith(
    sessionBlocks: sessionBlocks,
    pendingApprovals: pendingApprovals,
  );
}

/// A `session.status`/`session.idle` event is the only authoritative
/// confirmation that a session moved past a pending permission or
/// question; either clears any block recorded for [sessionId].
Map<String, SessionBlockReason> _clearSessionBlock(
  ConversationState state,
  String sessionId,
) {
  if (!state.sessionBlocks.containsKey(sessionId)) {
    return state.sessionBlocks;
  }
  return Map<String, SessionBlockReason>.of(state.sessionBlocks)
    ..remove(sessionId);
}

Map<String, PendingApproval> _clearPendingApproval(
  ConversationState state,
  String sessionId,
) {
  if (!state.pendingApprovals.containsKey(sessionId)) {
    return state.pendingApprovals;
  }
  return Map<String, PendingApproval>.of(state.pendingApprovals)
    ..remove(sessionId);
}

/// Clears [sessionId]'s pending-approval detail without touching
/// [ConversationState.sessionBlocks]. Used once a reply/reject request to
/// OpenCode succeeds: the approval dock's content is stale immediately,
/// but the queue itself must stay paused until an authoritative
/// `session.status`/`session.idle` event confirms the session actually
/// moved past it (see [SessionBlockedEvent] and `session_block_reason.
/// dart`).
ConversationState clearPendingApproval(
  ConversationState state,
  String sessionId,
) {
  final pendingApprovals = _clearPendingApproval(state, sessionId);
  if (identical(pendingApprovals, state.pendingApprovals)) {
    return state;
  }
  return state.copyWith(pendingApprovals: pendingApprovals);
}

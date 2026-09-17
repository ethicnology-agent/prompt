/// Pure mapping from [OpenCodeEventEnvelope] to typed conversation events.
///
/// [mapConversationEvent] is a total function: it never throws and never
/// performs I/O or logging. Malformed payloads, events for another session
/// or directory, and event types this conversation does not model all map
/// to `null` and are ignored by the caller.
library;

import '../../../data/remote/opencode_event_service.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import 'conversation_message.dart';
import 'pending_approval.dart';
import 'session_block_reason.dart';
import 'session_execution_state.dart';

/// A conversation-scoped event, already validated and reduced from raw
/// OpenCode JSON. See `conversation_state.dart` for the reducer that folds
/// these into a [ConversationState].
sealed class ConversationEvent {
  const ConversationEvent();

  String get sessionId;
}

/// A message was created or had its metadata (role, timing, ...) updated.
/// Carries no parts; existing parts for this message are preserved by the
/// reducer.
final class MessageUpdatedEvent extends ConversationEvent {
  const MessageUpdatedEvent({
    required this.sessionId,
    required this.messageId,
    required this.role,
  });

  @override
  final String sessionId;
  final String messageId;
  final ConversationRole role;
}

/// A message and all of its parts were removed.
final class MessageRemovedEvent extends ConversationEvent {
  const MessageRemovedEvent({required this.sessionId, required this.messageId});

  @override
  final String sessionId;
  final String messageId;
}

/// A full, authoritative snapshot of one message part.
final class MessagePartUpdatedEvent extends ConversationEvent {
  const MessagePartUpdatedEvent({required this.sessionId, required this.part});

  @override
  final String sessionId;
  final MessagePart part;
}

/// One part was removed from a message.
final class MessagePartRemovedEvent extends ConversationEvent {
  const MessagePartRemovedEvent({
    required this.sessionId,
    required this.messageId,
    required this.partId,
  });

  @override
  final String sessionId;
  final String messageId;
  final String partId;
}

/// The session's execution state changed to busy, idle, or retrying.
final class SessionStatusEvent extends ConversationEvent {
  const SessionStatusEvent({required this.sessionId, required this.state});

  @override
  final String sessionId;
  final SessionExecutionState state;
}

/// The session became idle. Distinct from a `session.status` event carrying
/// an idle state; the server emits both, and either is sufficient to settle
/// the session to idle.
final class SessionIdleEvent extends ConversationEvent {
  const SessionIdleEvent({required this.sessionId});

  @override
  final String sessionId;
}

/// A permission or question is pending for the session, reduced from
/// `permission.updated` or `question.asked`. [reason] is a coarse
/// classification used only to gate the queue (see
/// `session_block_reason.dart`); it never carries sensitive detail.
///
/// [detail] carries that detail — the permission's id/type/title, or the
/// question request's id and questions — for the approval UI to render.
/// It is `null` only when this event is constructed directly (for example
/// by an older caller or a test) rather than produced by
/// [mapConversationEvent]; every event this file maps from a real
/// `permission.updated`/`question.asked` payload carries one. A listener
/// must only ever show [detail] to the human being asked to approve it,
/// never log or persist it.
///
/// `permission.replied`/`question.replied`/`question.rejected` are
/// intentionally not modeled here: resuming a blocked queue is only ever
/// confirmed by an authoritative `session.status`/`session.idle` event,
/// never by a reply alone.
final class SessionBlockedEvent extends ConversationEvent {
  const SessionBlockedEvent({
    required this.sessionId,
    required this.reason,
    this.detail,
  });

  @override
  final String sessionId;
  final SessionBlockReason reason;
  final PendingApproval? detail;
}

/// Maps [envelope] to a [ConversationEvent] scoped to [sessionId].
///
/// Events for a different session, a different [directory] (when
/// [directory] is provided and the envelope reports one), an unmodeled
/// OpenCode event type, or a malformed payload all yield `null`.
ConversationEvent? mapConversationEvent(
  OpenCodeEventEnvelope envelope, {
  required String sessionId,
  String? directory,
}) {
  if (directory != null &&
      envelope.directory != null &&
      envelope.directory != directory) {
    return null;
  }

  final properties = envelope.payload['properties'];
  if (properties is! Map<String, dynamic>) {
    return null;
  }

  switch (envelope.type) {
    case 'message.updated':
      return _mapMessageUpdated(properties, sessionId);
    case 'message.removed':
      return _mapMessageRemoved(properties, sessionId);
    case 'message.part.updated':
      return _mapMessagePartUpdated(properties, sessionId);
    case 'message.part.removed':
      return _mapMessagePartRemoved(properties, sessionId);
    case 'session.status':
      return _mapSessionStatus(properties, sessionId);
    case 'session.idle':
      return _mapSessionIdle(properties, sessionId);
    case 'permission.updated':
      return _mapPermissionUpdated(properties, sessionId);
    case 'question.asked':
      return _mapQuestionAsked(properties, sessionId);
    default:
      return null;
  }
}

/// Maps one record returned by `GET /permission` for [sessionId].
/// The returned value is suitable for presentation only and must never be
/// logged or persisted.
PendingApproval? mapPendingPermission(
  Map<String, dynamic> json, {
  required String sessionId,
}) {
  final event = _mapPermissionUpdated(json, sessionId);
  return event is SessionBlockedEvent ? event.detail : null;
}

/// Maps one record returned by `GET /question` for [sessionId].
/// The returned value is suitable for presentation only and must never be
/// logged or persisted.
PendingApproval? mapPendingQuestion(
  Map<String, dynamic> json, {
  required String sessionId,
}) {
  final event = _mapQuestionAsked(json, sessionId);
  return event is SessionBlockedEvent ? event.detail : null;
}

ConversationEvent? _mapMessageUpdated(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final info = properties['info'];
  if (info is! Map<String, dynamic>) {
    return null;
  }
  final id = info['id'];
  final infoSessionId = info['sessionID'];
  final role = info['role'];
  if (id is! String || infoSessionId is! String || role is! String) {
    return null;
  }
  if (infoSessionId != sessionId) {
    return null;
  }
  final mappedRole = switch (role) {
    'user' => ConversationRole.user,
    'assistant' => ConversationRole.assistant,
    _ => null,
  };
  if (mappedRole == null) {
    return null;
  }
  return MessageUpdatedEvent(
    sessionId: infoSessionId,
    messageId: id,
    role: mappedRole,
  );
}

ConversationEvent? _mapMessageRemoved(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final messageId = properties['messageID'];
  if (eventSessionId is! String || messageId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  return MessageRemovedEvent(sessionId: eventSessionId, messageId: messageId);
}

ConversationEvent? _mapMessagePartUpdated(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final rawPart = properties['part'];
  if (rawPart is! Map<String, dynamic>) {
    return null;
  }
  final partSessionId = rawPart['sessionID'];
  if (partSessionId is! String || partSessionId != sessionId) {
    return null;
  }
  final part = _mapMessagePart(rawPart);
  if (part == null) {
    return null;
  }
  return MessagePartUpdatedEvent(sessionId: partSessionId, part: part);
}

MessagePart? _mapMessagePart(Map<String, dynamic> json) {
  final id = json['id'];
  final messageId = json['messageID'];
  final type = json['type'];
  if (id is! String || messageId is! String || type is! String) {
    return null;
  }
  switch (type) {
    case 'text':
      final text = json['text'];
      if (text is! String) {
        return null;
      }
      return TextMessagePart(id: id, messageId: messageId, text: text);
    case 'reasoning':
      final text = json['text'];
      if (text is! String) {
        return null;
      }
      return ReasoningMessagePart(id: id, messageId: messageId, text: text);
    case 'tool':
      final tool = json['tool'];
      final state = json['state'];
      if (tool is! String || state is! Map<String, dynamic>) {
        return null;
      }
      final status = _mapToolStatus(state['status']);
      if (status == null) {
        return null;
      }
      return ToolMessagePart(
        id: id,
        messageId: messageId,
        tool: tool,
        status: status,
        summary: _toolSummary(tool, state['input']),
        error: state['error'] is String ? state['error'] as String : null,
      );
    default:
      return OtherMessagePart(id: id, messageId: messageId, partType: type);
  }
}

String? _toolSummary(String tool, Object? input) {
  if (input is! Map<String, dynamic>) return null;
  final description = input['description'];
  if (tool == 'task' && description is String && description.isNotEmpty) {
    return description;
  }
  for (final key in const ['command', 'filePath', 'path', 'pattern', 'query']) {
    final value = input[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

ToolPartStatus? _mapToolStatus(Object? status) {
  return switch (status) {
    'pending' => ToolPartStatus.pending,
    'running' => ToolPartStatus.running,
    'completed' => ToolPartStatus.completed,
    'error' => ToolPartStatus.error,
    _ => null,
  };
}

ConversationEvent? _mapMessagePartRemoved(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final messageId = properties['messageID'];
  final partId = properties['partID'];
  if (eventSessionId is! String || messageId is! String || partId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  return MessagePartRemovedEvent(
    sessionId: eventSessionId,
    messageId: messageId,
    partId: partId,
  );
}

ConversationEvent? _mapSessionStatus(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final status = properties['status'];
  if (eventSessionId is! String || status is! Map<String, dynamic>) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  final state = _mapSessionExecutionState(status);
  // A native gateway failure is an explicit loss of executable context. It
  // must replace stale busy/permission state without ever authorizing dispatch.
  // Continue ignoring unrecognized/malformed future statuses.
  if (state is SessionExecutionUnknown && status['type'] != 'error') {
    return null;
  }
  return SessionStatusEvent(sessionId: eventSessionId, state: state);
}

SessionExecutionState _mapSessionExecutionState(Object? value) {
  return switch (parseOpenCodeSessionStatus(value)) {
    OpenCodeSessionStatusBusy() => const SessionBusy(),
    OpenCodeSessionStatusIdle() => const SessionIdle(),
    OpenCodeSessionStatusRetry(:final attempt, :final message, :final next) =>
      SessionRetrying(
        attempt: attempt,
        message: message,
        nextAttemptAtMillis: next,
      ),
    OpenCodeSessionStatusUnknown() => const SessionExecutionUnknown(),
  };
}

ConversationEvent? _mapSessionIdle(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  if (eventSessionId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  return SessionIdleEvent(sessionId: eventSessionId);
}

/// `permission.updated`'s `properties` is the OpenCode `Permission` object
/// itself (not a wrapper): `id`, `type`, `sessionID`, `title`, and
/// optionally `pattern`/`metadata`/`callID`. `pattern` and `metadata` are
/// never read here — only `id`, `type`, and `title` reach [PendingApproval]
/// detail, which is shown only to the human approving it (see
/// `pending_approval.dart`).
ConversationEvent? _mapPermissionUpdated(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  if (eventSessionId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  final type = properties['type'];
  final reason = type == 'question'
      ? SessionBlockReason.question
      : SessionBlockReason.permission;

  final id = properties['id'];
  final title = properties['title'];
  final detail = (id is String && type is String && title is String)
      ? PendingPermissionApproval(
          sessionId: eventSessionId,
          permissionId: id,
          toolType: type,
          title: title,
        )
      : null;

  return SessionBlockedEvent(
    sessionId: eventSessionId,
    reason: reason,
    detail: detail,
  );
}

/// `question.asked`'s `properties` is the OpenCode `QuestionRequest`
/// object: `id`, `sessionID`, `questions` (each `question`, `header`,
/// `options`, and optionally `multiple`/`custom`), and an optional `tool`
/// reference this app does not need. A malformed request — including any
/// question in it — maps to `null` rather than a partial approval.
ConversationEvent? _mapQuestionAsked(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final requestId = properties['id'];
  final rawQuestions = properties['questions'];
  if (eventSessionId is! String ||
      requestId is! String ||
      rawQuestions is! List) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }

  final questions = <QuestionPrompt>[];
  for (final rawQuestion in rawQuestions) {
    if (rawQuestion is! Map<String, dynamic>) {
      return null;
    }
    final prompt = _mapQuestionPrompt(rawQuestion);
    if (prompt == null) {
      return null;
    }
    questions.add(prompt);
  }
  if (questions.isEmpty) {
    return null;
  }

  return SessionBlockedEvent(
    sessionId: eventSessionId,
    reason: SessionBlockReason.question,
    detail: PendingQuestionApproval(
      sessionId: eventSessionId,
      requestId: requestId,
      questions: questions,
    ),
  );
}

QuestionPrompt? _mapQuestionPrompt(Map<String, dynamic> json) {
  final question = json['question'];
  final header = json['header'];
  final rawOptions = json['options'];
  if (question is! String || header is! String || rawOptions is! List) {
    return null;
  }

  final options = <QuestionOption>[];
  for (final rawOption in rawOptions) {
    if (rawOption is! Map<String, dynamic>) {
      return null;
    }
    final label = rawOption['label'];
    final description = rawOption['description'];
    if (label is! String || description is! String) {
      return null;
    }
    options.add(QuestionOption(label: label, description: description));
  }

  final multiple = json['multiple'];
  final custom = json['custom'];
  return QuestionPrompt(
    question: question,
    header: header,
    options: options,
    multiple: multiple is bool ? multiple : false,
    // OpenCode's own default is `true` when the field is absent.
    allowsCustomAnswer: custom is bool ? custom : true,
  );
}

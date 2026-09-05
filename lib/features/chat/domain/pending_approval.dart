/// Full detail of one pending, human-actionable approval for the active
/// session: a tool-call permission (`bash`, `edit`, `webfetch`, ...), or a
/// set of questions the agent's `question` tool is asking.
///
/// This is deliberately a much richer type than [SessionBlockReason] (see
/// `session_block_reason.dart`): it exists only to render the accessible
/// approval dock/sheet a human must act on. It never gates the queue by
/// itself — dispatch stays governed by [SessionBlockReason] and the
/// authoritative `session.status`/`session.idle` rule, exactly as before
/// this type existed.
///
/// A [PendingApproval] is reduced only from a live SSE event
/// (`permission.updated` or `question.asked`) received while a session is
/// activated; it is never fetched, reconciled, or cached beyond that
/// activation, and it is never written to Drift, a log, or a diagnostic
/// export. [PendingPermissionApproval.title] and every [QuestionPrompt]
/// field may describe a sensitive command, path, or question the agent
/// wants answered — that sensitivity is exactly why this type exists (so a
/// human can actually review it), but it is also exactly why a caller must
/// only ever render it to that human, never log or persist it.
library;

sealed class PendingApproval {
  const PendingApproval({required this.sessionId});

  final String sessionId;

  /// Identity of the request awaiting an answer.
  ///
  /// The live conversation state is rebuilt on every SSE event, so the same
  /// pending request arrives as a fresh object again and again. Anything that
  /// must survive those rebuilds — a form the user is filling in, for one —
  /// has to compare this rather than the object.
  String get id => switch (this) {
    PendingPermissionApproval(:final permissionId) => permissionId,
    PendingQuestionApproval(:final requestId) => requestId,
  };
}

/// A pending tool-call permission, reduced from a `permission.updated` SSE
/// event's `Permission` payload.
final class PendingPermissionApproval extends PendingApproval {
  const PendingPermissionApproval({
    required super.sessionId,
    required this.permissionId,
    required this.toolType,
    required this.title,
  });

  /// OpenCode's `Permission.id`, required to respond via `POST
  /// /session/{id}/permissions/{permissionID}`.
  final String permissionId;

  /// OpenCode's `Permission.type` (for example `bash`, `edit`, `webfetch`).
  final String toolType;

  /// OpenCode's `Permission.title`: the only human-readable summary the
  /// server provides. May describe a sensitive command or path.
  final String title;
}

/// One selectable choice within a [QuestionPrompt].
class QuestionOption {
  const QuestionOption({required this.label, required this.description});

  final String label;
  final String description;
}

/// One question the agent's `question` tool is asking, as part of a
/// [PendingQuestionApproval].
class QuestionPrompt {
  const QuestionPrompt({
    required this.question,
    required this.header,
    required this.options,
    this.multiple = false,
    this.allowsCustomAnswer = true,
  });

  /// The complete question text.
  final String question;

  /// A short label (OpenCode caps this at 30 characters).
  final String header;

  /// The choices OpenCode suggests for this question.
  final List<QuestionOption> options;

  /// Whether more than one option may be selected.
  final bool multiple;

  /// Whether typing a free-text answer is allowed in addition to, or
  /// instead of, the suggested [options]. Defaults to `true`, matching
  /// OpenCode's own default when the field is absent.
  final bool allowsCustomAnswer;
}

/// A pending multi-question request from the agent's `question` tool,
/// reduced from a `question.asked` SSE event.
final class PendingQuestionApproval extends PendingApproval {
  const PendingQuestionApproval({
    required super.sessionId,
    required this.requestId,
    required this.questions,
  });

  /// OpenCode's `QuestionRequest.id`, required to reply or reject via
  /// `POST /question/{requestID}/reply` or `POST /question/{requestID}/
  /// reject`.
  final String requestId;

  /// Every question this request is asking, in order. A reply must supply
  /// exactly one answer list per entry, in the same order.
  final List<QuestionPrompt> questions;
}

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
/// A [PendingApproval] is reconciled from live SSE events and pending-request
/// REST snapshots while a session is activated. It is never cached beyond that
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
}

/// Known scope of OpenCode's suggested reusable permission rules. This is not
/// a session-only grant. The server controls the lifetime of these rules.
enum PermissionRuleScope { directoryInstance }

/// A pending tool-call permission, from either legacy `permission.updated`
/// or modern `permission.asked` / pending-request REST data.
final class PendingPermissionApproval extends PendingApproval {
  const PendingPermissionApproval({
    required super.sessionId,
    required this.permissionId,
    required this.toolType,
    required this.title,
    this.patterns = const [],
    this.alwaysPatterns = const [],
    this.ruleScope,
    this.workingDirectory,
    this.reason,
  });

  /// OpenCode's `Permission.id`, required to respond via `POST
  /// /session/{id}/permissions/{permissionID}`.
  final String permissionId;

  /// Legacy `type` or modern `permission` (for example `bash`, `edit`).
  final String toolType;

  /// Legacy title or modern exact command / requested patterns. May describe
  /// a sensitive command or path.
  final String title;

  /// Exact requested targets and the potentially broader reusable rules.
  final List<String> patterns;
  final List<String> alwaysPatterns;
  final PermissionRuleScope? ruleScope;
  final String? workingDirectory;
  final String? reason;

  bool get hasKnownAlwaysScope =>
      ruleScope == PermissionRuleScope.directoryInstance &&
      alwaysPatterns.isNotEmpty;
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

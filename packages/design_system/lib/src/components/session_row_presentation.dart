import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The dot shown when a session has finished and has something unread.
const Color sessionReadyDotColor = Color(0xFF007AFF);

/// The dot shown when a session is stopped, waiting for a human decision.
const Color sessionBlockedDotColor = Color(0xFFFF9500);

/// What a session row is doing, as far as its presentation is concerned.
enum SessionRowState {
  /// Nothing in flight.
  idle,

  /// The agent is producing a turn.
  thinking,

  /// The agent stopped and needs a permission decision.
  permissionRequired,

  /// The agent stopped and needs an answer to a question.
  inputRequired,
}

/// How a session row renders its two progress signals.
@immutable
class SessionRowPresentation {
  const SessionRowPresentation({
    required this.shimmerTitle,
    required this.dotColor,
  });

  /// Whether the title sweeps to show work in flight.
  final bool shimmerTitle;

  /// The dot that replaces the timestamp, or null to keep the timestamp.
  final Color? dotColor;

  @override
  bool operator ==(Object other) =>
      other is SessionRowPresentation &&
      other.shimmerTitle == shimmerTitle &&
      other.dotColor == dotColor;

  @override
  int get hashCode => Object.hash(shimmerTitle, dotColor);
}

/// Keeps a row's two progress signals mutually exclusive.
///
/// Work in flight is carried by the title sweep; only something the user should
/// act on replaces the ordinary timestamp with a dot. A faded row — one whose
/// machine is gone — shows neither, because nothing is happening on it.
///
/// This mirrors Happy's `resolveFlatSessionRowPresentation`
/// (`sources/utils/flatSessionRowPresentation.ts`), including the order of the
/// branches: a blocked session outranks unread, and a thinking session never
/// shows a dot.
SessionRowPresentation resolveSessionRowPresentation({
  required SessionRowState state,
  required bool hasUnread,
  required bool faded,
}) {
  if (faded) {
    return const SessionRowPresentation(shimmerTitle: false, dotColor: null);
  }
  if (state == SessionRowState.permissionRequired ||
      state == SessionRowState.inputRequired) {
    return const SessionRowPresentation(
      shimmerTitle: false,
      dotColor: sessionBlockedDotColor,
    );
  }
  if (state == SessionRowState.thinking) {
    return const SessionRowPresentation(shimmerTitle: true, dotColor: null);
  }
  if (hasUnread) {
    return const SessionRowPresentation(
      shimmerTitle: false,
      dotColor: sessionReadyDotColor,
    );
  }
  return const SessionRowPresentation(shimmerTitle: false, dotColor: null);
}

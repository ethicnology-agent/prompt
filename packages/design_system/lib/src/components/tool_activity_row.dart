import 'package:flutter/material.dart';

import '../prompt_typography.dart';

/// Vertical breathing room around an activity row.
const double _rowMargin = 2;

/// The row's own minimum height, before its text wraps.
const double _rowMinHeight = 28;

/// A tool call reported as one line of activity.
///
/// The reference gives a tool a full card only when it has something worth
/// showing — a diff, a todo list, a task tree. Everything else is one
/// transparent line: a glyph, what the tool is doing, and how long it has been
/// doing it (`ToolView.tsx`, `compactContainer` and `compactHeader`; the rule
/// itself is `shouldUseCompactToolRow` in `utils/toolDisplay.ts`, which reduces
/// to "compact unless this tool has its own view").
///
/// Dressing every tool as a card, as Prompt did, buried the conversation under
/// chrome: a one-line `ls` occupied as much of the screen as a paragraph of
/// reasoning.
class ToolActivityRow extends StatelessWidget {
  const ToolActivityRow({
    required this.icon,
    required this.label,
    this.statusIcon,
    this.statusColor,
    this.elapsed,
    this.onTap,
    this.expanded = false,
    super.key,
  });

  /// What kind of operation this is.
  final IconData icon;

  /// What the tool is doing, in its own words. Truncated to one line.
  final String label;

  /// Outcome, once there is one.
  final IconData? statusIcon;
  final Color? statusColor;

  /// How long the call has been running, shown only while it runs.
  final Duration? elapsed;

  /// Reveals the call's output, when there is any to reveal.
  final VoidCallback? onTap;

  /// Whether that output is currently revealed.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowMinHeight),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: Center(child: Icon(icon, size: 18, color: secondary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  height: 20 / 15,
                  color: secondary,
                ),
              ),
            ),
            if (elapsed case final running?) ...[
              const SizedBox(width: 8),
              Text(
                '${(running.inMilliseconds / 1000).toStringAsFixed(1)}s',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  fontFamily: promptMonoFamily,
                  color: secondary,
                ),
              ),
            ],
            if (statusIcon case final glyph?) ...[
              const SizedBox(width: 8),
              Icon(glyph, size: 20, color: statusColor ?? secondary),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _rowMargin),
      child: onTap == null
          ? Semantics(container: true, label: label, child: row)
          : Semantics(
              container: true,
              button: true,
              expanded: expanded,
              label: label,
              onTap: onTap,
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(4),
                  excludeFromSemantics: true,
                  child: row,
                ),
              ),
            ),
    );
  }
}

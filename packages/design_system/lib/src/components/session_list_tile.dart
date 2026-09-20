import 'package:flutter/material.dart';

import 'session_row_presentation.dart';
import 'shimmer_text.dart';

/// Left inset of the row, and where the avatar slot starts.
const double _rowPaddingLeft = 16;

/// The avatar occupies a fixed slot so every title lines up, whatever the
/// avatar itself draws inside it.
const double _avatarSlot = 60;

/// Gap between the avatar slot and the text column.
const double _avatarGap = 12;

/// Where the text column — and therefore the divider — begins.
const double _contentInset = _rowPaddingLeft + _avatarSlot + _avatarGap;

/// Fixed width of the timestamp/dot slot, so titles truncate at one place.
const double _topRightSlotWidth = 56;

/// Diameter of the dot that replaces the timestamp.
const double _topRightDotSize = 20;

/// One session in the list.
///
/// Laid out after Happy's `FlatSessionRow`
/// (`sources/components/FlatSessionRow.tsx`): a 60-pixel avatar slot, a title
/// at 17, the project at 15, and a third line that carries the worktree and the
/// git counters rather than a status word. Progress is not spelled out in text —
/// see [resolveSessionRowPresentation] for why the sweep and the dot never
/// appear together.
class SessionListTile extends StatelessWidget {
  const SessionListTile({
    super.key,
    required this.identifier,
    required this.title,
    required this.project,
    required this.timestamp,
    required this.onTap,
    required this.avatar,
    this.state = SessionRowState.idle,
    this.statusLabel = '',
    this.onLongPress,
    this.selected = false,
    this.showDivider = true,
    this.unread = false,
    this.faded = false,
    this.nested = false,
    this.worktree,
    this.hasDraft = false,
    this.changedFiles,
    this.insertions = 0,
    this.deletions = 0,
  });

  final String identifier;
  final String title;
  final String project;
  final String timestamp;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The identity mark. Injected so the row stays free of avatar policy.
  final Widget avatar;

  /// What the session is doing, which drives the sweep and the dot.
  final SessionRowState state;

  /// The spoken form of [state], for assistive technology only. Nothing in the
  /// row prints it, the way Happy keeps the third line for workspace facts.
  final String statusLabel;

  final bool selected;
  final bool showDivider;
  final bool unread;

  /// The session's machine is gone, so the row is quiet and greyed.
  final bool faded;

  final bool nested;

  /// Worktree or branch this session runs in, when it is not the main one.
  final String? worktree;

  /// An unsent draft is waiting in this session's composer.
  final bool hasDraft;

  /// Number of changed files, or null when the session reports none.
  final int? changedFiles;
  final int insertions;
  final int deletions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = scheme.onSurfaceVariant;
    final presentation = resolveSessionRowPresentation(
      state: state,
      hasUnread: unread,
      faded: faded,
    );
    final enabled = onTap != null || onLongPress != null;
    final label = [
      title,
      project,
      if (statusLabel.isNotEmpty) 'Session activity: $statusLabel',
      if (worktree != null && worktree!.isNotEmpty) 'Worktree: $worktree',
      if (hasDraft) 'Unsent draft',
      if (presentation.dotColor == sessionBlockedDotColor) 'Waiting for you',
      if (presentation.dotColor == sessionReadyDotColor) 'Unread',
      timestamp,
      if (nested) 'Child session',
    ].where((part) => part.isNotEmpty).join(', ');

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      height: 22 / 17,
      color: faded ? secondary : scheme.onSurface,
    );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      hint: onLongPress == null ? null : 'Long press for session actions',
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? scheme.surfaceContainerHighest : scheme.surface,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            excludeFromSemantics: true,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _rowPaddingLeft,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _avatarSlot,
                        height: _avatarSlot,
                        child: Opacity(
                          opacity: faded ? 0.5 : 1,
                          child: Center(child: avatar),
                        ),
                      ),
                      const SizedBox(width: _avatarGap),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _titleRow(
                              context,
                              presentation,
                              titleStyle,
                              secondary,
                            ),
                            Text(
                              project,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 15,
                                height: 20 / 15,
                                color: secondary,
                              ),
                            ),
                            _workspaceRow(context, secondary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showDivider)
                  const PositionedDirectional(
                    start: _contentInset,
                    end: 0,
                    bottom: 0,
                    child: Divider(height: 1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleRow(
    BuildContext context,
    SessionRowPresentation presentation,
    TextStyle? titleStyle,
    Color secondary,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: presentation.shimmerTitle
              ? ShimmerText(
                  text: title,
                  style: titleStyle,
                  baseColor: secondary,
                  highlightColor: theme.colorScheme.onSurface,
                )
              : Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: _topRightSlotWidth,
          height: 22,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: presentation.dotColor != null
                ? Container(
                    key: const ValueKey('session-row-dot'),
                    width: _topRightDotSize,
                    height: _topRightDotSize,
                    decoration: BoxDecoration(
                      color: presentation.dotColor,
                      shape: BoxShape.circle,
                    ),
                  )
                : Text(
                    timestamp,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      height: 22 / 13,
                      color: secondary,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// The third line: where the session runs, and what it has touched.
  ///
  /// Kept in the layout even when empty so a row never changes height as work
  /// starts and stops.
  Widget _workspaceRow(BuildContext context, Color secondary) {
    final theme = Theme.of(context);
    final meta = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      height: 18 / 13,
      color: secondary,
    );
    final branch = worktree;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            if (nested) ...[
              Icon(Icons.subdirectory_arrow_right, size: 13, color: secondary),
              const SizedBox(width: 4),
            ],
            if (branch != null && branch.isNotEmpty) ...[
              Flexible(
                child: Text(
                  branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.account_tree_outlined, size: 13, color: secondary),
            ],
            const Spacer(),
            if (hasDraft) ...[
              Icon(Icons.edit_outlined, size: 13, color: secondary),
              const SizedBox(width: 4),
            ],
            if (changedFiles != null)
              _GitLineChanges(
                changedFiles: changedFiles!,
                insertions: insertions,
                deletions: deletions,
                style: meta,
              ),
          ],
        ),
      ),
    );
  }
}

/// `3 files  +84  −12`, in the row's metadata size.
class _GitLineChanges extends StatelessWidget {
  const _GitLineChanges({
    required this.changedFiles,
    required this.insertions,
    required this.deletions,
    required this.style,
  });

  final int changedFiles;
  final int insertions;
  final int deletions;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$changedFiles', style: style),
        const SizedBox(width: 4),
        Icon(Icons.description_outlined, size: 13, color: style?.color),
        if (insertions > 0) ...[
          const SizedBox(width: 4),
          Text(
            '+$insertions',
            style: style?.copyWith(color: const Color(0xFF28A745)),
          ),
        ],
        if (deletions > 0) ...[
          const SizedBox(width: 4),
          Text('−$deletions', style: style?.copyWith(color: tokens.error)),
        ],
      ],
    );
  }
}

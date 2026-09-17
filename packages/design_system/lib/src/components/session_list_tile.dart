import 'package:flutter/material.dart';

import '../spinning_icon.dart';
import 'identity_avatar.dart';

class SessionListTile extends StatelessWidget {
  const SessionListTile({
    super.key,
    required this.identifier,
    required this.title,
    required this.project,
    required this.status,
    required this.timestamp,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showDivider = true,
    this.unread,
    this.nested = false,
    this.statusIcon,
    this.inProgress = false,
  });

  final String identifier;
  final String title;
  final String project;
  final String status;
  final String timestamp;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool showDivider;
  final bool? unread;
  final bool nested;
  final IconData? statusIcon;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = scheme.onSurfaceVariant;
    final timestampWidth =
        (56 * MediaQuery.textScalerOf(context).scale(13) / 13).clamp(
          56.0,
          112.0,
        );
    final enabled = onTap != null || onLongPress != null;
    final label = [
      title,
      project,
      'Session activity: $status',
      timestamp,
      if (unread == true) 'Unread',
      if (nested) 'Child session',
    ].where((part) => part.isNotEmpty).join(', ');

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
          color: selected ? scheme.primaryContainer : scheme.surface,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            excludeFromSemantics: true,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IdentityAvatar(identifier: identifier),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontSize: 17,
                                          height: 22 / 17,
                                          color: scheme.onSurface,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: timestampWidth,
                                  child: unread == true
                                      ? Align(
                                          alignment:
                                              AlignmentDirectional.centerEnd,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: scheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          timestamp,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.end,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontSize: 13,
                                                height: 22 / 13,
                                                color: secondary,
                                              ),
                                        ),
                                ),
                              ],
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
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                if (nested) ...[
                                  Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 13,
                                    color: secondary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                if (statusIcon != null) ...[
                                  SpinningIcon(
                                    key: const ValueKey(
                                      'session-activity-spin',
                                    ),
                                    icon: statusIcon!,
                                    size: 13,
                                    color: secondary,
                                    spinning: inProgress,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 13,
                                      height: 18 / 13,
                                      color: secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showDivider)
                  PositionedDirectional(
                    start: 88,
                    end: 0,
                    bottom: 0,
                    child: Divider(
                      height: 1,
                      thickness: 1 / MediaQuery.devicePixelRatioOf(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

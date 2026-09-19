import 'package:flutter/material.dart';

import '../prompt_ui_tokens.dart';
import 'app_button.dart';

class AppActionSheetOption<T> {
  const AppActionSheetOption({
    required this.value,
    required this.label,
    required this.icon,
    this.description,
    this.enabled = true,
    this.destructive = false,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? description;
  final bool enabled;
  final bool destructive;
  final bool dividerBefore;
}

/// A compact, scrollable action surface intended for modal bottom sheets.
class AppActionSheet<T> extends StatelessWidget {
  const AppActionSheet({
    required this.title,
    required this.options,
    required this.onSelected,
    required this.onClose,
    super.key,
  });

  final String title;
  final List<AppActionSheetOption<T>> options;
  final ValueChanged<T> onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Semantics(
                      header: true,
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close $title',
                  onPressed: onClose,
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options) ...[
                      if (option.dividerBefore)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Divider(color: colors.outlineVariant),
                        ),
                      Semantics(
                        button: true,
                        enabled: option.enabled,
                        child: ListTile(
                          minTileHeight: 52,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              PromptUiTokens.controlRadius,
                            ),
                          ),
                          enabled: option.enabled,
                          leading: Icon(
                            option.icon,
                            size: 21,
                            color: !option.enabled
                                ? colors.onSurface.withValues(alpha: 0.38)
                                : option.destructive
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                          title: Text(option.label),
                          subtitle: option.description == null
                              ? null
                              : Text(option.description!),
                          titleTextStyle: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: !option.enabled
                                    ? colors.onSurface.withValues(alpha: 0.38)
                                    : option.destructive
                                    ? colors.error
                                    : colors.onSurface,
                              ),
                          subtitleTextStyle: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                          onTap: option.enabled
                              ? () => onSelected(option.value)
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

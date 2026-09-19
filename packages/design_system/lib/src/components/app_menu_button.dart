import 'package:flutter/material.dart';

import '../prompt_ui_tokens.dart';

class AppMenuOption<T> {
  const AppMenuOption({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.selected = false,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool enabled;
  final bool selected;
  final bool dividerBefore;
}

class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.tooltip,
    required this.optionsBuilder,
    required this.onSelected,
    this.icon,
  });

  final String tooltip;
  final List<AppMenuOption<T>> Function(BuildContext context) optionsBuilder;
  final ValueChanged<T> onSelected;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: icon,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiTokens.cardRadius),
      ),
      color: theme.colorScheme.surfaceContainerHigh,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in optionsBuilder(context)) ...[
          if (option.dividerBefore) const PopupMenuDivider(),
          PopupMenuItem<T>(
            value: option.value,
            enabled: option.enabled,
            height: 52,
            child: Semantics(
              selected: option.selected,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 24,
                    child: Icon(
                      option.selected ? Icons.check_rounded : option.icon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

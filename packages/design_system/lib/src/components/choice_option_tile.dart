import 'package:flutter/material.dart';

/// A controlled, full-width option with a visible description and native focus.
class ChoiceOptionTile extends StatelessWidget {
  const ChoiceOptionTile({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.description,
    this.multiple = false,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String? description;
  final bool selected;
  final bool multiple;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = enabled ? onPressed : null;
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        label: description == null || description!.isEmpty
            ? label
            : '$label\n$description',
        checked: selected,
        inMutuallyExclusiveGroup: !multiple,
        enabled: action != null,
        onTap: action,
        excludeSemantics: true,
        child: ListTile(
          enabled: action != null,
          selected: selected,
          onTap: action,
          minTileHeight: 48,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          selectedColor: theme.colorScheme.onSurface,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          leading: Icon(
            multiple
                ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                : (selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
            size: 22,
            color: action == null
                ? theme.disabledColor
                : selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(label, style: theme.textTheme.bodyMedium),
          subtitle: description == null || description!.isEmpty
              ? null
              : Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}

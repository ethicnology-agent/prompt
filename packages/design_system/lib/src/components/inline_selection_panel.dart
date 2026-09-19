import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_button.dart';

class InlineSelectionOption<T> {
  const InlineSelectionOption({
    required this.value,
    required this.label,
    this.description,
    this.groupLabel,
    this.icon,
  });
  final T value;
  final String label;
  final String? description;
  final String? groupLabel;
  final IconData? icon;
}

/// Immediate, controlled selection inside an existing composer layout.
/// Keeps native focus traversal and never creates implicit default options.
class InlineSelectionPanel<T> extends StatefulWidget {
  const InlineSelectionPanel({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onClose,
    this.listHeight = 240,
    this.radioIndicator = true,
  });

  final String title;
  final List<InlineSelectionOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final VoidCallback onClose;

  /// Maximum choices viewport height; short lists use only their content height.
  final double listHeight;
  final bool radioIndicator;

  @override
  State<InlineSelectionPanel<T>> createState() =>
      _InlineSelectionPanelState<T>();
}

class _InlineSelectionPanelState<T> extends State<InlineSelectionPanel<T>> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final options = widget.options;
    final selected = widget.selected;
    final onSelected = widget.onSelected;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Material(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        clipBehavior: Clip.antiAlias,
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
                          widget.title.toUpperCase(),
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
                    icon: Icons.close,
                    tooltip: 'Close ${widget.title} choices',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: widget.listHeight.clamp(0.0, double.infinity),
                  ),
                  child: options.isEmpty
                      ? const SizedBox(
                          height: 48,
                          child: Center(child: Text('No available choices')),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          child: ListView.builder(
                            key: ValueKey('inline-selection-${widget.title}'),
                            controller: _scrollController,
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            primary: false,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.manual,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options[index];
                              final group = option.groupLabel;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (group != null &&
                                      (index == 0 ||
                                          options[index - 1].groupLabel !=
                                              group))
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        8,
                                        12,
                                        4,
                                      ),
                                      child: Semantics(
                                        header: true,
                                        child: Text(
                                          group,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Semantics(
                                    selected: selected == option.value,
                                    child: ListTile(
                                      minTileHeight: 48,
                                      minLeadingWidth: 18,
                                      horizontalTitleGap: 12,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 2,
                                          ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      selectedColor: colors.primary,
                                      textColor: colors.onSurface,
                                      titleTextStyle: TextStyle(
                                        fontSize: 14,
                                        height: 1.25,
                                        fontWeight: FontWeight.w500,
                                        color: onSelected == null
                                            ? colors.onSurface.withValues(
                                                alpha: 0.38,
                                              )
                                            : selected == option.value
                                            ? colors.primary
                                            : colors.onSurface,
                                      ),
                                      subtitleTextStyle: TextStyle(
                                        fontSize: 12,
                                        height: 1.3,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      leading: option.icon != null
                                          ? Icon(option.icon, size: 18)
                                          : widget.radioIndicator
                                          ? Icon(
                                              selected == option.value
                                                  ? Icons.radio_button_checked
                                                  : Icons
                                                        .radio_button_unchecked,
                                              size: 18,
                                              color: onSelected == null
                                                  ? colors.onSurface.withValues(
                                                      alpha: 0.38,
                                                    )
                                                  : selected == option.value
                                                  ? colors.primary
                                                  : colors.onSurfaceVariant,
                                            )
                                          : selected == option.value
                                          ? Icon(
                                              Icons.check,
                                              size: 18,
                                              color: colors.primary,
                                            )
                                          : const SizedBox(width: 18),
                                      title: Text(option.label),
                                      subtitle: option.description == null
                                          ? null
                                          : Text(option.description!),
                                      selected: selected == option.value,
                                      enabled: onSelected != null,
                                      onTap: onSelected == null
                                          ? null
                                          : () => onSelected(option.value),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

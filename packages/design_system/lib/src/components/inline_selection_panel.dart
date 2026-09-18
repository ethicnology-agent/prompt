import 'package:flutter/material.dart';

import 'app_button.dart';

class InlineSelectionOption<T> {
  const InlineSelectionOption({
    required this.value,
    required this.label,
    this.description,
    this.groupLabel,
  });
  final T value;
  final String label;
  final String? description;
  final String? groupLabel;
}

/// Immediate, controlled selection inside an existing composer layout.
/// Does not manage focus, routes, keyboards, or implicit default options.
class InlineSelectionPanel<T> extends StatelessWidget {
  const InlineSelectionPanel({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onClose,
    this.listHeight = 240,
    this.radioIndicator = false,
  });

  final String title;
  final List<InlineSelectionOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final VoidCallback onClose;
  final double listHeight;
  final bool radioIndicator;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AppIconButton(
              icon: Icons.close,
              tooltip: 'Close $title choices',
              onPressed: onClose,
            ),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        SizedBox(
          height: listHeight.clamp(48.0, double.infinity),
          child: options.isEmpty
              ? const Center(child: Text('No available choices'))
              : ListView.builder(
                  key: ValueKey('inline-selection-$title'),
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
                                options[index - 1].groupLabel != group))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Semantics(
                              header: true,
                              child: Text(
                                group,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ),
                        Semantics(
                          selected: selected == option.value,
                          child: ListTile(
                            minTileHeight: 48,
                            leading: radioIndicator
                                ? Icon(
                                    selected == option.value
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                  )
                                : selected == option.value
                                ? const Icon(Icons.check)
                                : const SizedBox(width: 24),
                            title: Text(option.label),
                            subtitle: option.description == null
                                ? null
                                : Text(option.description!),
                            selected: selected == option.value,
                            enabled: onSelected != null,
                            onTap: onSelected == null
                                ? null
                                : () => onSelected!(option.value),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

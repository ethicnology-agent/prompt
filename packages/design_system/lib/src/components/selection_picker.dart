import 'package:flutter/material.dart';

import 'app_button.dart';
import 'app_text_field.dart';

class SelectionOption<T> {
  const SelectionOption({
    required this.value,
    required this.label,
    this.description,
  });
  final T value;
  final String label;
  final String? description;
}

class SelectionPicker<T> extends StatefulWidget {
  const SelectionPicker({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onApply,
    required this.onCancel,
    this.includeDefault = true,
  });
  final String title;
  final List<SelectionOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onApply;
  final VoidCallback onCancel;

  /// Whether to offer the generic null-valued default alongside caller options.
  final bool includeDefault;

  @override
  State<SelectionPicker<T>> createState() => _SelectionPickerState<T>();
}

class _SelectionPickerState<T> extends State<SelectionPicker<T>> {
  late T? _selected = widget.selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where(
          (option) => '${option.label} ${option.description ?? ''}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Search ${widget.title.toLowerCase()}',
                  prefixIcon: Icons.search,
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    AppButton(
                      label: 'Cancel',
                      variant: AppButtonVariant.tertiary,
                      onPressed: widget.onCancel,
                    ),
                    AppButton(
                      label: 'Apply',
                      onPressed: () => widget.onApply(_selected),
                    ),
                  ],
                ),
                if (widget.includeDefault)
                  ListTile(
                    title: const Text('Default'),
                    selected: _selected == null,
                    leading: Icon(
                      _selected == null
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () => setState(() => _selected = null),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverList.builder(
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              return ListTile(
                title: Text(option.label),
                subtitle: option.description == null
                    ? null
                    : Text(option.description!),
                selected: _selected == option.value,
                leading: Icon(
                  _selected == option.value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => setState(() => _selected = option.value),
              );
            },
          ),
        ),
        if (options.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matching options'),
            ),
          ),
      ],
    );
  }
}

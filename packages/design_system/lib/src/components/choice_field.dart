import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_button.dart';
import 'inline_selection_panel.dart';

/// A controlled form choice using the shared immediate-selection surface.
///
/// Values must be unique within [options]. Use [scopeKey] when this field may
/// be reused for a different server, session, or other owner.
class ChoiceField<T> extends StatefulWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.scopeKey,
    this.placeholder = 'Choose',
  });

  final String label;
  final List<InlineSelectionOption<T>> options;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final Object? scopeKey;
  final String placeholder;

  @override
  State<ChoiceField<T>> createState() => _ChoiceFieldState<T>();
}

class _ChoiceFieldState<T> extends State<ChoiceField<T>> {
  DialogRoute<void>? _route;
  ValueNotifier<int>? _updates;

  @override
  void didUpdateWidget(ChoiceField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey) {
      _dismiss();
    } else if (_updates != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _route != null && _updates != null) {
          _updates!.value++;
        }
      });
    }
  }

  void _dismiss() {
    final route = _route;
    _route = null;
    if (route == null) return;
    void remove() {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
  }

  Future<void> _open() async {
    if (!mounted ||
        _route != null ||
        widget.onSelected == null ||
        widget.options.isEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final scope = widget.scopeKey;
    final updates = ValueNotifier(0);
    _updates = updates;
    late final DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      builder: (context) => ValueListenableBuilder<int>(
        valueListenable: updates,
        builder: (context, _, _) {
          if (!mounted || !identical(_route, route)) return const SizedBox();
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: 560,
                child: InlineSelectionPanel<T>(
                  title: widget.label,
                  options: widget.options,
                  selected: widget.selected,
                  listHeight: (constraints.maxHeight - 56).clamp(0.0, 344.0),
                  onClose: _dismiss,
                  onSelected: widget.onSelected == null
                      ? null
                      : (value) {
                          if (!mounted ||
                              !identical(_route, route) ||
                              scope != widget.scopeKey) {
                            return;
                          }
                          final callback = widget.onSelected;
                          if (callback == null) return;
                          for (final option in widget.options) {
                            if (option.value == value) {
                              _dismiss();
                              callback(option.value);
                              return;
                            }
                          }
                        },
                ),
              ),
            ),
          );
        },
      ),
    );
    _route = route;
    try {
      await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      if (identical(_route, route)) _route = null;
      if (identical(_updates, updates)) _updates = null;
      updates.dispose();
    }
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options
        .where((option) => option.value == widget.selected)
        .firstOrNull;
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        label: '${widget.label}: ${selected?.label ?? widget.placeholder}',
        icon: Icons.expand_more_rounded,
        variant: AppButtonVariant.secondary,
        leftAligned: true,
        onPressed: widget.onSelected == null || widget.options.isEmpty
            ? null
            : _open,
      ),
    );
  }
}

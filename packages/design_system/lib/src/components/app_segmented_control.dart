import 'package:flutter/material.dart';

class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A single-choice control that keeps every segment reachable on compact
/// screens without forcing feature code to reproduce sizing and scrolling.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final segment in segments)
          ButtonSegment<T>(
            value: segment.value,
            label: Text(segment.label),
            icon: segment.icon == null ? null : Icon(segment.icon),
          ),
      ],
      selected: {selected},
      onSelectionChanged: onSelected == null
          ? null
          : (values) => onSelected!(values.single),
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      ),
    ),
  );
}

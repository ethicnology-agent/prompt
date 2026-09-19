import 'package:flutter/material.dart';

/// A shared single-choice filter with a full touch target and stable semantics.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.semanticLabel,
    this.icon,
  });

  final String label;
  final String? semanticLabel;
  final IconData? icon;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    avatar: icon == null ? null : Icon(icon, size: 18),
    label: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: semanticLabel ?? label,
    ),
    selected: selected,
    onSelected: onSelected,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

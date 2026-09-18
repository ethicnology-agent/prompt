import 'package:flutter/material.dart';

/// A bounded composer choice: compact text, never a compact touch target.
class CompactChoiceButton extends StatelessWidget {
  const CompactChoiceButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: semanticLabel,
    excludeFromSemantics: true,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        semanticsLabel: semanticLabel,
      ),
    ),
  );
}

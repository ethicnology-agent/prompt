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
        // The reference writes these in its secondary text colour, not the
        // brand accent: they report the current setting, they do not invite a
        // tap the way a link does.
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
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

import 'package:flutter/material.dart';

/// Shared visual shell for draft and in-session composers.
class ComposerSurface extends StatelessWidget {
  const ComposerSurface({
    required this.child,
    this.contentPadding = const EdgeInsets.all(8),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 4,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(padding: contentPadding, child: child),
    );
  }
}

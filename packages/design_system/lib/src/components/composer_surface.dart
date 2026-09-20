import 'package:flutter/material.dart';

import '../mobile_composer_metrics.dart';

/// Shared visual shell for draft and in-session composers.
///
/// Both wear the same shell, at the geometry in [MobileComposerMetrics]: the
/// two composers differ in what they hold, never in where they sit.
class ComposerSurface extends StatelessWidget {
  const ComposerSurface({
    required this.child,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: MobileComposerMetrics.shellInset,
      vertical: MobileComposerMetrics.shellPaddingTop,
    ),
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
        borderRadius: BorderRadius.circular(MobileComposerMetrics.shellRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(padding: contentPadding, child: child),
    );
  }
}

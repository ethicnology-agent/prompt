import 'package:flutter/material.dart';

import '../prompt_color_tokens.dart';

/// A compact, text-backed status marker for persistent interface state.
///
/// The visible label and semantic announcement ensure the state is never
/// communicated by color alone.
class AppStatusIndicator extends StatelessWidget {
  const AppStatusIndicator({
    required this.label,
    this.semanticLabel,
    this.liveRegion = false,
    super.key,
  });

  final String label;
  final String? semanticLabel;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        theme.extension<PromptTokens>()?.success ?? theme.colorScheme.primary;
    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      liveRegion: liveRegion,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

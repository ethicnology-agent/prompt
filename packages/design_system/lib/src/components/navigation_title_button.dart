import 'package:flutter/material.dart';

/// An accessible, bounded navigation target for a toolbar title.
class NavigationTitleButton extends StatelessWidget {
  const NavigationTitleButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.subtitle,
    this.subtitleSegments = const [],
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;
  final String? subtitle;
  final List<NavigationTitleSegment> subtitleSegments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.2,
    );
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.2,
    );
    final scaler = MediaQuery.textScalerOf(context);
    // Deciding this from the incoming constraints does not work: a toolbar
    // hands its title a loose constraint covering the whole screen, not its own
    // 64, so the check passed and a second line overflowed the header at 200%
    // text — twice, once with the constraint read directly and once with an
    // unbounded fallback. Judge it on the text scale instead, which is the same
    // threshold the execution controls and the creation dock already use.
    const scaleCeiling = 18.0;
    final fitsTwoLines = scaler.scale(14) <= scaleCeiling;
    final details = subtitleSegments.isEmpty
        ? subtitle
        : subtitleSegments.map((segment) => segment.text).join(' ');
    final fullLabel = details == null || details.isEmpty
        ? label
        : '$label\n$details';
    return Tooltip(
      message: fullLabel,
      excludeFromSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          alignment: AlignmentDirectional.centerStart,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
        child: Semantics(
          label: semanticLabel,
          value: details,
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Keep the title legible in a fixed-height toolbar at large
              // text sizes. The full subtitle remains in semantics/tooltip.
              if (details != null && details.isNotEmpty && fitsTwoLines)
                if (subtitleSegments.isEmpty)
                  Text(
                    details,
                    style: subtitleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final (index, segment)
                            in subtitleSegments.indexed) ...[
                          if (index > 0) const TextSpan(text: ' '),
                          TextSpan(
                            text: segment.text,
                            style: subtitleStyle.copyWith(
                              color: switch (segment.tone) {
                                NavigationTitleSegmentTone.neutral =>
                                  subtitleStyle.color,
                                NavigationTitleSegmentTone.positive =>
                                  theme.colorScheme.primary,
                                NavigationTitleSegmentTone.negative =>
                                  theme.colorScheme.error,
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

enum NavigationTitleSegmentTone { neutral, positive, negative }

class NavigationTitleSegment {
  const NavigationTitleSegment(
    this.text, {
    this.tone = NavigationTitleSegmentTone.neutral,
  });

  final String text;
  final NavigationTitleSegmentTone tone;
}

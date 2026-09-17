import 'package:flutter/material.dart';

import '../prompt_color_tokens.dart';

/// A grouped settings surface, independent of the actions inside it.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  /// Keeps cards distinct from their page in both supported appearances.
  static Color pageColor(ThemeData theme) => theme.brightness == Brightness.dark
      ? theme.colorScheme.surface
      : const Color(0xfff5f5f5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        Material(
          color:
              theme.extension<PromptTokens>()?.panel ??
              scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTileTheme(
            data: ListTileThemeData(
              iconColor: scheme.primary,
              textColor: scheme.onSurface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              minLeadingWidth: 24,
              minTileHeight: 64,
              titleTextStyle: theme.textTheme.bodyLarge,
              subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            child: ExpansionTileTheme(
              data: ExpansionTileThemeData(
                iconColor: scheme.primary,
                collapsedIconColor: scheme.primary,
                textColor: scheme.onSurface,
                collapsedTextColor: scheme.onSurface,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: const Border(),
                collapsedShape: const Border(),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(start: 56),
                        child: Divider(height: 1, thickness: 0.5),
                      ),
                    children[index],
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

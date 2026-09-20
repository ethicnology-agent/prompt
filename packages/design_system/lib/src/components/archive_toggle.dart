import 'package:flutter/material.dart';

/// The divider-with-a-label that opens and closes the archive.
///
/// Matches Happy's `archiveToggle` in `sources/components/SessionsList.tsx`: a
/// centred 14-point label in the secondary colour, flanked by two hairline
/// rules that take the remaining width, inset 24 a side, with 20 above and 12
/// below.
///
/// Happy only renders it when the list actually holds archived sessions, so a
/// user who has never archived anything never sees it. Callers are expected to
/// keep that rule.
class ArchiveToggle extends StatelessWidget {
  const ArchiveToggle({
    required this.hidden,
    required this.onPressed,
    super.key,
  });

  /// Whether the archive is currently collapsed, which decides the wording.
  final bool hidden;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = hidden ? 'Show archived' : 'Hide archived';
    final rule = Expanded(
      child: Divider(
        height: 1 / MediaQuery.devicePixelRatioOf(context),
        thickness: 1 / MediaQuery.devicePixelRatioOf(context),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                rule,
                const SizedBox(width: 12),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                rule,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

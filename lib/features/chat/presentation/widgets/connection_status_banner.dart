import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// A slim, non-dismissible banner announcing [text] above the transcript.
/// `liveRegion: true` makes a screen reader announce a status change (for
/// example connected -> reconnecting) without the user having to find and
/// re-read the banner themselves, matching this app's rule that
/// connection state must not rely on color or animation alone.
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner(
    this.text, {
    this.reconnecting = false,
    this.onRetry,
    super.key,
  });

  final String text;
  final bool reconnecting;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                reconnecting ? Icons.sync_rounded : Icons.sync_problem_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (onRetry != null)
                AppButton(
                  label: 'Retry',
                  variant: AppButtonVariant.tertiary,
                  onPressed: onRetry,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String directoryName(String directory) {
  final normalized = directory.replaceAll('\\', '/');
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? directory : segments.last;
}

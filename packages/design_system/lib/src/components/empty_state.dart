import 'package:flutter/material.dart';

/// What a surface shows when it has nothing to show.
///
/// The reference gives every empty surface the same three-part shape: a large
/// outlined glyph, a bold sentence naming the situation, and a quieter one
/// saying what to do about it, with an optional action beneath. Measured on its
/// unreachable-machine home: a 56 glyph, a 24 title, a 16 subtitle, all centred
/// with the action as a full-bleed pill.
///
/// Prompt was leaving a single grey sentence floating mid-screen, which reads
/// as a loading state rather than an answer.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.error = false,
    super.key,
  });

  final IconData icon;

  /// The situation, in one line.
  final String title;

  /// What the user can do about it.
  final String message;

  /// The way out, when there is one.
  final Widget? action;

  /// Whether the situation is a failure rather than simply nothing to show.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Enlarged text turns three short lines into a dozen, and an empty state
    // is often handed a fixed slot. Scroll rather than overflow.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          // Three centred lines running the width of a tablet are hard to read.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Stretch would blow the glyph up to the column's width.
              Center(
                child: Icon(
                  icon,
                  size: 56,
                  color: error
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontSize: 24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action case final way?) ...[const SizedBox(height: 24), way],
            ],
          ),
        ),
      ),
    );
  }
}

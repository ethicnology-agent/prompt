import 'package:flutter/material.dart';

/// Presentation-only entry point; creation still goes through SessionsViewModel.
class NewSessionDock extends StatelessWidget {
  const NewSessionDock({
    required this.onCreate,
    required this.onTerminal,
    this.draftController,
    super.key,
  });

  final VoidCallback? onCreate;
  final VoidCallback? onTerminal;
  final TextEditingController? draftController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (onTerminal != null)
              IconButton(
                tooltip: 'Remote terminal',
                onPressed: onTerminal,
                icon: const Icon(Icons.terminal_rounded),
              ),
            Expanded(
              child: draftController != null
                  ? TextField(
                      controller: draftController,
                      enabled: onCreate != null,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'What would you like to do?',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    )
                  : TextButton(
                      onPressed: onCreate,
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size(48, 48),
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: const Text('What would you like to do?'),
                    ),
            ),
            IconButton.filled(
              tooltip: 'New session',
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

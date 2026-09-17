import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';

/// Presentation-only entry point; creation still goes through SessionsViewModel.
class NewSessionDock extends StatelessWidget {
  const NewSessionDock({
    required this.onCreate,
    required this.onTerminal,
    this.draftController,
    this.focusNode,
    super.key,
  });

  final VoidCallback? onCreate;
  final VoidCallback? onTerminal;
  final TextEditingController? draftController;
  final FocusNode? focusNode;

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
              AppIconButton(
                icon: Icons.terminal_rounded,
                tooltip: 'Remote terminal',
                onPressed: onTerminal,
              ),
            Expanded(
              child: draftController != null
                  ? AppTextField(
                      controller: draftController,
                      focusNode: focusNode,
                      enabled: onCreate != null,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      hint: 'What would you like to do?',
                      variant: AppTextFieldVariant.borderless,
                    )
                  : AppButton(
                      variant: AppButtonVariant.tertiary,
                      tone: AppButtonTone.subtle,
                      leftAligned: true,
                      onPressed: onCreate,
                      label: 'What would you like to do?',
                    ),
            ),
            AppIconButton(
              variant: AppIconButtonVariant.filled,
              tooltip: 'New session from draft',
              onPressed: onCreate,
              icon: Icons.add_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

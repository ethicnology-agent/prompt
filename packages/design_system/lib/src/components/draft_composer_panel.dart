import 'package:flutter/material.dart';

import 'app_button.dart';
import 'app_text_field.dart';
import 'composer_action_bar.dart';

/// A real creation setting. A missing callback makes the row read-only.
class CreationConfigurationRow extends StatelessWidget {
  const CreationConfigurationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    enabled: onTap != null,
    child: Tooltip(
      message: value,
      excludeFromSemantics: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon),
        title: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        enabled: onTap != null,
        onTap: onTap,
        minVerticalPadding: 8,
        minTileHeight: 48,
      ),
    ),
  );
}

/// Inline creation configuration and draft, with no backend assumptions.
/// The parent provides the height remaining above the keyboard.
class DraftComposerPanel extends StatelessWidget {
  const DraftComposerPanel({
    required this.controller,
    required this.focusNode,
    required this.expanded,
    this.enabled = true,
    this.readOnly = false,
    this.attachments,
    this.configuration,
    this.actions,
    this.onSubmit,
    this.onAttach,
    this.onTerminal,
    this.onClose,
    this.onChanged,
    this.hint = 'What would you like to do?',
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool expanded;
  final bool enabled;
  final bool readOnly;
  final Widget? attachments;
  final Widget? configuration;
  final Widget? actions;
  final VoidCallback? onSubmit;
  final VoidCallback? onAttach;
  final VoidCallback? onTerminal;
  final VoidCallback? onClose;
  final ValueChanged<String>? onChanged;
  final String hint;

  Widget _submit() => AppIconButton(
    variant: AppIconButtonVariant.filled,
    tooltip: 'New session from draft',
    onPressed: onSubmit,
    icon: Icons.arrow_upward_rounded,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      reverse: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expanded && configuration != null)
            Material(
              key: const ValueKey('draft-configuration-surface'),
              color: scheme.surface,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: configuration!,
              ),
            ),
          Material(
            key: const ValueKey('draft-composer-card'),
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?attachments,
                  Row(
                    children: [
                      if (!expanded && onTerminal != null)
                        AppIconButton(
                          icon: Icons.terminal_rounded,
                          tooltip: 'Remote terminal',
                          onPressed: onTerminal,
                        ),
                      Expanded(
                        child: AppTextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: enabled,
                          readOnly: readOnly,
                          minLines: 1,
                          maxLines: 4,
                          onChanged: onChanged,
                          textInputAction: TextInputAction.newline,
                          hint: hint,
                          variant: AppTextFieldVariant.borderless,
                        ),
                      ),
                      if (!expanded) _submit(),
                    ],
                  ),
                  if (expanded)
                    ComposerActionBar(
                      leading: [
                        if (onAttach != null)
                          AppIconButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Attach files',
                            onPressed: onAttach,
                          ),
                        if (onTerminal != null)
                          AppIconButton(
                            icon: Icons.terminal_rounded,
                            tooltip: 'Remote terminal',
                            onPressed: onTerminal,
                          ),
                        if (onClose != null)
                          AppIconButton(
                            icon: Icons.keyboard_hide_outlined,
                            tooltip: 'Close new session options',
                            onPressed: onClose,
                          ),
                      ],
                      controls: actions,
                      trailing: _submit(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

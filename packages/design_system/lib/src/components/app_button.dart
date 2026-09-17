import 'package:flutter/material.dart';
import '../prompt_color_tokens.dart';

enum AppButtonVariant { primary, secondary, tertiary, destructive }

enum AppButtonTone { standard, subtle, userMessage }

enum AppIconButtonVariant { standard, filled, tonal }

enum AppIconButtonTone { standard, recording }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.busy = false,
    this.autofocus = false,
    this.loading = false,
    this.leftAligned = false,
    this.tone = AppButtonTone.standard,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool busy;
  final bool autofocus;
  final bool loading;
  final bool leftAligned;
  final AppButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final action = busy ? null : onPressed;
    final theme = Theme.of(context);
    final foreground = switch (tone) {
      AppButtonTone.standard => null,
      AppButtonTone.subtle => theme.colorScheme.onSurfaceVariant,
      AppButtonTone.userMessage =>
        theme.extension<PromptTokens>()?.userMessageForeground ??
            theme.colorScheme.onPrimaryContainer,
    };
    final style = ButtonStyle(
      alignment: leftAligned ? Alignment.centerLeft : null,
      foregroundColor: foreground == null
          ? null
          : WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ? null : foreground,
            ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: leftAligned
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        if (busy || loading || icon != null) ...[
          if (busy || loading)
            const _ActivityIndicator()
          else
            Icon(icon, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: leftAligned ? TextAlign.start : TextAlign.center,
          ),
        ),
      ],
    );
    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
        style: style,
        onPressed: action,
        autofocus: autofocus,
        child: content,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        style: style,
        onPressed: action,
        autofocus: autofocus,
        child: content,
      ),
      AppButtonVariant.tertiary => TextButton(
        style: style,
        onPressed: action,
        autofocus: autofocus,
        child: content,
      ),
      AppButtonVariant.destructive => FilledButton(
        onPressed: action,
        autofocus: autofocus,
        style: FilledButton.styleFrom(
          alignment: leftAligned ? Alignment.centerLeft : null,
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        child: content,
      ),
    };
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
    this.loading = false,
    this.variant = AppIconButtonVariant.standard,
    this.tone = AppIconButtonTone.standard,
    this.isSelected,
    this.selectedIcon,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;
  final bool loading;
  final AppIconButtonVariant variant;
  final AppIconButtonTone tone;
  final bool? isSelected;
  final IconData? selectedIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<PromptTokens>();
    final style = IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      backgroundColor: tone == AppIconButtonTone.recording
          ? tokens?.userMessageForeground ??
                theme.colorScheme.onPrimaryContainer
          : null,
      foregroundColor: tone == AppIconButtonTone.recording
          ? tokens?.userMessageBackground ?? theme.colorScheme.primaryContainer
          : null,
    );
    final iconWidget = Semantics(
      label: tooltip,
      child: busy || loading
          ? const ExcludeSemantics(child: _ActivityIndicator())
          : Icon(icon),
    );
    final action = busy ? null : onPressed;
    final selected = busy || loading || selectedIcon == null
        ? null
        : Semantics(label: tooltip, child: Icon(selectedIcon));
    final button = switch (variant) {
      AppIconButtonVariant.standard => IconButton(
        tooltip: tooltip,
        onPressed: action,
        icon: iconWidget,
        style: style,
        isSelected: isSelected,
        selectedIcon: selected,
      ),
      AppIconButtonVariant.filled => IconButton.filled(
        tooltip: tooltip,
        onPressed: action,
        icon: iconWidget,
        style: style,
        isSelected: isSelected,
        selectedIcon: selected,
      ),
      AppIconButtonVariant.tonal => IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: action,
        icon: iconWidget,
        style: style,
        isSelected: isSelected,
        selectedIcon: selected,
      ),
    };
    return button;
  }
}

class _ActivityIndicator extends StatelessWidget {
  const _ActivityIndicator();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: IconTheme.of(context).color,
      semanticsLabel: 'In progress',
    ),
  );
}

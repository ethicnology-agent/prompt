import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';

/// Presentation-only entry point; creation still goes through SessionsViewModel.
class NewSessionDock extends StatefulWidget {
  const NewSessionDock({
    required this.onCreate,
    required this.onTerminal,
    this.draftController,
    this.focusNode,
    this.configuration,
    this.actions,
    this.composerWrapper,
    this.onDismissChoice,
    this.expanded,
    this.enabled = true,
    this.readOnly = false,
    this.pageMode = false,
    this.attachments,
    this.onExpandedChanged,
    this.onChanged,
    this.onAttach,
    this.hint = 'Plan, ask, build…',
    super.key,
  });

  final VoidCallback? onCreate;
  final VoidCallback? onTerminal;
  final TextEditingController? draftController;
  final FocusNode? focusNode;
  final Widget? configuration;
  final Widget? actions;
  final Widget Function(Widget composer)? composerWrapper;
  final VoidCallback? onDismissChoice;
  final bool? expanded;
  final bool enabled;
  final bool readOnly;
  final bool pageMode;
  final Widget? attachments;
  final ValueChanged<bool>? onExpandedChanged;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onAttach;
  final String hint;

  @override
  State<NewSessionDock> createState() => _NewSessionDockState();
}

class _NewSessionDockState extends State<NewSessionDock> {
  late FocusNode _focus;
  bool _ownsFocus = false;
  bool _focused = false;

  bool get _expanded =>
      widget.expanded ?? (_focused && widget.configuration != null);

  @override
  void initState() {
    super.initState();
    _bindFocus();
  }

  void _bindFocus() {
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode();
    _focused = _focus.hasFocus;
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_focus.hasFocus == _focused) return;
    setState(() => _focused = _focus.hasFocus);
    if (widget.expanded == null) {
      widget.onExpandedChanged?.call(_expanded);
    } else if (_focused && widget.configuration != null) {
      // Controlled expansion is a request, not an echo of the parent's old
      // value. Losing focus to a picker must not close its underlying panel.
      widget.onExpandedChanged?.call(true);
    }
  }

  void _close() {
    _focus.unfocus();
    if (widget.expanded != null) widget.onExpandedChanged?.call(false);
  }

  @override
  void didUpdateWidget(NewSessionDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_focusChanged);
      if (_ownsFocus) _focus.dispose();
      _bindFocus();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.draftController case final controller?) {
      return PopScope(
        canPop: widget.pageMode ? widget.onDismissChoice == null : !_expanded,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _expanded) {
            if (widget.onDismissChoice case final dismiss?) {
              dismiss();
            } else {
              _close();
            }
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Bounded parents already account for their keyboard/safe-area.
            final media = MediaQuery.of(context);
            final maxHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : (media.size.height -
                          media.viewInsets.bottom -
                          media.padding.vertical -
                          kToolbarHeight -
                          24)
                      .clamp(64.0, double.infinity);
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: DraftComposerPanel(
                controller: controller,
                focusNode: _focus,
                expanded: _expanded,
                pageMode: widget.pageMode,
                enabled: widget.enabled,
                readOnly: widget.readOnly,
                attachments: widget.attachments,
                configuration: widget.configuration,
                actions: widget.actions,
                composerWrapper: widget.composerWrapper,
                onSubmit: widget.onCreate,
                onTerminal: widget.onTerminal,
                onAttach: widget.onAttach,
                onChanged: widget.onChanged,
                hint: widget.hint,
              ),
            );
          },
        ),
      );
    }
    return ComposerSurface(
      child: Row(
        children: [
          if (widget.onTerminal != null)
            AppIconButton(
              icon: Icons.terminal_rounded,
              tooltip: 'Remote terminal',
              onPressed: widget.onTerminal,
            ),
          Expanded(
            child: AppButton(
              variant: AppButtonVariant.tertiary,
              tone: AppButtonTone.subtle,
              leftAligned: true,
              onPressed: widget.onCreate,
              label: widget.hint,
            ),
          ),
          AppIconButton(
            variant: AppIconButtonVariant.filled,
            tooltip: 'New session from draft',
            onPressed: widget.onCreate,
            icon: Icons.add_rounded,
          ),
        ],
      ),
    );
  }
}

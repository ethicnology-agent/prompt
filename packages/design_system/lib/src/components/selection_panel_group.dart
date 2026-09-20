import 'package:flutter/material.dart';

import 'app_button.dart';

/// One desktop surface for related immediate choices. Each section receives
/// its bounded height and owns its scroll position; no business state lives here.
class SelectionPanelGroup extends StatefulWidget {
  const SelectionPanelGroup({
    required this.maxHeight,
    required this.primaryBuilder,
    required this.onClose,
    this.topBuilder,
    this.secondaryBuilder,
    super.key,
  });

  final double maxHeight;
  final Widget Function(double height) primaryBuilder;
  final Widget Function(double height)? topBuilder;
  final Widget Function(double height)? secondaryBuilder;
  final VoidCallback onClose;

  @override
  State<SelectionPanelGroup> createState() => _SelectionPanelGroupState();
}

class _SelectionPanelGroupState extends State<SelectionPanelGroup> {
  final _focusScope = FocusScopeNode(debugLabel: 'Execution settings');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Opening by pointer already focused the trigger in another scope.
      // Explicitly transfer focus once, after the overlay controls are mounted.
      _focusScope.requestFocus(_focusScope.traversalDescendants.firstOrNull);
    });
  }

  @override
  void dispose() {
    _focusScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = widget.maxHeight;
    final topBuilder = widget.topBuilder;
    final primaryBuilder = widget.primaryBuilder;
    final secondaryBuilder = widget.secondaryBuilder;
    final colors = Theme.of(context).colorScheme;
    final bodyHeight = (maxHeight - 56).clamp(0.0, double.infinity);
    final topHeight = topBuilder == null ? 0.0 : bodyHeight * .45;
    final bottomHeight = (bodyHeight - topHeight - (topBuilder == null ? 0 : 9))
        .clamp(0.0, double.infinity);
    return BlockSemantics(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: FocusScope(
          node: _focusScope,
          child: Material(
            color: colors.surface,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: .18),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .65),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Semantics(
                            header: true,
                            child: const Text('Execution settings'),
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: Icons.close,
                        tooltip: 'Close execution settings',
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  if (topBuilder != null) ...[
                    topBuilder(topHeight),
                    const Divider(height: 9),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: primaryBuilder(bottomHeight)),
                      if (secondaryBuilder != null) ...[
                        SizedBox(
                          height: bottomHeight,
                          child: const VerticalDivider(width: 17),
                        ),
                        Expanded(child: secondaryBuilder(bottomHeight)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

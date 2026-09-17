import 'package:flutter/material.dart';

class ComposerActionBar extends StatelessWidget {
  const ComposerActionBar({
    super.key,
    this.leading = const [],
    this.controls,
    required this.trailing,
  });

  final List<Widget> leading;
  final Widget? controls;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controlWidth =
          120 * MediaQuery.textScalerOf(context).scale(14) / 14;
      final stacked =
          controls != null &&
          constraints.maxWidth < leading.length * 56 + controlWidth + 56;
      final actions = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (controls != null && !stacked) ...[
            Wrap(spacing: 8, runSpacing: 8, children: leading),
            const SizedBox(width: 8),
            Expanded(child: controls!),
          ] else
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: leading)),
          const SizedBox(width: 8),
          trailing,
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked) ...[controls!, const SizedBox(height: 4)],
          actions,
        ],
      );
    },
  );
}

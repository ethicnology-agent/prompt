import 'package:flutter/material.dart';

import '../mobile_composer_metrics.dart';

/// The single row of actions under a composer's text area.
///
/// It never becomes two rows. The reference keeps this row at a fixed
/// [MobileComposerMetrics.actionRowHeight] and lets the middle controls shrink
/// or truncate, so the composer's height changes only when the text does — a
/// second row would move the send button out from under the thumb mid-sentence.
class ComposerActionBar extends StatelessWidget {
  const ComposerActionBar({
    super.key,
    this.leading = const [],
    this.controls,
    required this.trailing,
  });

  /// Round actions pinned to the left, such as attachment and permission mode.
  final List<Widget> leading;

  /// The flexible middle, usually the model and effort choosers.
  final Widget? controls;

  /// The send or stop action.
  final Widget trailing;

  /// Above this scaled size the row is allowed to grow, because the controls
  /// can no longer be read on one line. It is the threshold the execution
  /// controls already use to drop their roomy layout.
  static const double _scaleCeiling = 18;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(14);
    final row = Row(
      children: [
        for (final action in leading) ...[action, const SizedBox(width: 4)],
        if (controls case final middle?)
          Expanded(child: middle)
        else
          const Spacer(),
        const SizedBox(width: MobileComposerMetrics.primaryActionMarginLeft),
        trailing,
      ],
    );
    if (scaled > _scaleCeiling) {
      // Enlarged text cannot be read on one line. Parity yields to legibility
      // here rather than clipping the model name to nothing.
      return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: MobileComposerMetrics.actionRowHeight,
        ),
        child: row,
      );
    }
    return SizedBox(height: MobileComposerMetrics.actionRowHeight, child: row);
  }
}

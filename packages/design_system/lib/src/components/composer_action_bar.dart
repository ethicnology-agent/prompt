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

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // A minimum, not a fixed height. The row is 42 in the reference and 48
    // here, and stays there whenever its contents fit; it grows only when the
    // middle wraps, which happens when enlarged text or a narrow phone leaves
    // no room to read the labels on one line. Pinning the height instead
    // clipped the wrapped row and put the controls out of reach.
    constraints: const BoxConstraints(
      minHeight: MobileComposerMetrics.actionRowHeight,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final action in leading) ...[action, const SizedBox(width: 4)],
        if (controls case final middle?)
          Expanded(child: middle)
        else
          const Spacer(),
        const SizedBox(width: MobileComposerMetrics.primaryActionMarginLeft),
        trailing,
      ],
    ),
  );
}

import 'package:flutter/widgets.dart';

/// A readable content width that also fills narrow panes and preserves height.
class ContentColumn extends StatelessWidget {
  const ContentColumn({required this.child, this.maxWidth = 800, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

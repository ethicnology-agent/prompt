import 'package:flutter/widgets.dart';

enum PromptSizeClass { phone, tablet, desktop }

abstract final class PromptBreakpoints {
  static const double tablet = 600;
  static const double desktop = 900;
}

extension PromptSizeClassProperties on PromptSizeClass {
  bool get isPhone => this == PromptSizeClass.phone;
  bool get isTablet => this == PromptSizeClass.tablet;
  bool get isDesktop => this == PromptSizeClass.desktop;
}

PromptSizeClass promptSizeClassForWidth(double width) {
  if (width < PromptBreakpoints.tablet) return PromptSizeClass.phone;
  if (width < PromptBreakpoints.desktop) return PromptSizeClass.tablet;
  return PromptSizeClass.desktop;
}

class PromptAdaptiveBuilder extends StatelessWidget {
  const PromptAdaptiveBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, PromptSizeClass sizeClass)
  builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          builder(context, promptSizeClassForWidth(constraints.maxWidth)),
    );
  }
}

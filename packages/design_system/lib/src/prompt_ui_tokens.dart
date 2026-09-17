import 'package:flutter/widgets.dart';

import 'adaptive_layout.dart';

abstract final class PromptUiTokens {
  static const double compactPagePadding = 16;
  static const double widePagePadding = 24;
  static const double panelGap = 12;
  static const double cardRadius = 14;
  static const double controlRadius = 12;
}

EdgeInsets promptPagePadding(PromptSizeClass sizeClass) {
  return EdgeInsets.all(
    sizeClass.isPhone
        ? PromptUiTokens.compactPagePadding
        : PromptUiTokens.widePagePadding,
  );
}

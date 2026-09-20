/// Canonical visual metrics for the compact mobile composer.
///
/// The home draft and the in-session composer deliberately carry different
/// controls, but their shell, input and action geometry must stay identical, so
/// that moving between the two never shifts the thing under the user's thumb.
/// The values come from the reference's own table
/// (`sources/components/agentInputLayout.ts`), which states the same rule.
abstract final class MobileComposerMetrics {
  /// Corner radius of the composer shell.
  static const double shellRadius = 30;

  /// Inset between the shell edge and its contents.
  static const double shellInset = 10;

  static const double shellPaddingTop = 8;
  static const double shellPaddingBottom = 8;

  /// Resting height of the text area, before it grows with the text.
  static const double inputMinHeight = 44;

  /// Where the text area stops growing and starts scrolling.
  static const double inputMaxHeight = 120;

  static const double inputFontSize = 16;
  static const double inputLineHeight = 22;
  static const double inputPaddingTop = 4;
  static const double inputPaddingBottom = 4;

  /// Smallest touch target this project ships, whatever the reference draws.
  ///
  /// The reference paints its round actions at 42 and widens the touch area
  /// with a 15-point slop, which lands well past this floor. Flutter expresses
  /// the same idea by padding the target to 48, so Prompt keeps 48 as the box
  /// and accepts a composer 6 taller than the reference's rather than shipping
  /// a 42 target with no slop.
  static const double minimumTapTarget = 48;

  /// Height of the single row of actions under the text area.
  ///
  /// The reference never stacks this into a second row: controls shrink or
  /// truncate instead, so the composer's height only changes when the text
  /// itself grows. Its own value is 42; see [minimumTapTarget].
  static const double actionRowHeight = minimumTapTarget;

  /// Diameter of a round action in that row.
  static const double actionSize = minimumTapTarget;

  static const double addIconSize = 26;

  /// Height of a pill-shaped secondary control, such as the model chooser.
  static const double secondaryActionHeight = 40;

  static const double effortWidth = 64;
  static const double primaryActionSize = 42;
  static const double primaryActionMarginLeft = 8;

  /// Extra height the shell takes when an attachment strip is present.
  static const double attachmentExtraHeight = 72;

  /// Height of the shell when the text area is at rest.
  static const double baseHeight =
      shellPaddingTop + inputMinHeight + actionRowHeight + shellPaddingBottom;

  /// Everything but the text area.
  static const double chromeHeight = baseHeight - inputMinHeight;

  /// Height of the shell for a given measured text height.
  static double resolveHeight(
    double inputHeight, {
    bool hasAttachments = false,
  }) {
    final container = inputHeight + inputPaddingTop + inputPaddingBottom;
    return chromeHeight +
        (container < inputMinHeight ? inputMinHeight : container) +
        (hasAttachments ? attachmentExtraHeight : 0);
  }
}

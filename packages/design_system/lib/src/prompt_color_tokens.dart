import 'package:flutter/material.dart';

/// Semantic colors shared by Prompt presentation features.
///
/// The neutral ramp and the primary button are taken literally from Happy's
/// runtime palette (`packages/happy-app/sources/theme.ts`, the Android
/// branches). Happy is a monochrome application: black, white and a short grey
/// ramp, with hue reserved for meaning — a dot for a session that needs you, a
/// tinted gutter in a diff. Deriving these from a seed colour, as Material does,
/// is what made Prompt read as a different product.
@immutable
class PromptTokens extends ThemeExtension<PromptTokens> {
  const PromptTokens({
    required this.panel,
    required this.panelRaised,
    required this.subtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.diffAdd,
    required this.diffDelete,
    required this.userMessageBackground,
    required this.userMessageForeground,
    required this.userMessageBorder,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.groupedBackground,
    required this.inputBackground,
    required this.inputPlaceholder,
    required this.buttonPrimaryBackground,
    required this.buttonPrimaryTint,
    required this.buttonPrimaryDisabled,
  });

  final Color panel;
  final Color panelRaised;
  final Color subtle;
  final Color success;
  final Color warning;
  final Color danger;
  final Color diffAdd;
  final Color diffDelete;
  final Color userMessageBackground;
  final Color userMessageForeground;
  final Color userMessageBorder;

  /// One step off the page: section cards and quiet containers.
  final Color surfaceHigh;

  /// Two steps off the page: the resting fill of a round composer action.
  final Color surfaceHighest;

  /// The page behind grouped settings lists.
  final Color groupedBackground;

  /// Fill of a text field.
  final Color inputBackground;

  /// Placeholder text inside a field.
  final Color inputPlaceholder;

  /// Primary call to action.
  ///
  /// The reference inverts it rather than keeping one fill: black with white
  /// text in light, near-white with near-black text in dark
  /// (`RoundButton.tsx`). A black button on its black dark page would be
  /// invisible, which is how this was caught — in a dark-mode pass, after a
  /// first attempt shipped black for both.
  final Color buttonPrimaryBackground;
  final Color buttonPrimaryTint;
  final Color buttonPrimaryDisabled;

  @override
  PromptTokens copyWith({
    Color? panel,
    Color? panelRaised,
    Color? subtle,
    Color? success,
    Color? warning,
    Color? danger,
    Color? diffAdd,
    Color? diffDelete,
    Color? userMessageBackground,
    Color? userMessageForeground,
    Color? userMessageBorder,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? groupedBackground,
    Color? inputBackground,
    Color? inputPlaceholder,
    Color? buttonPrimaryBackground,
    Color? buttonPrimaryTint,
    Color? buttonPrimaryDisabled,
  }) => PromptTokens(
    panel: panel ?? this.panel,
    panelRaised: panelRaised ?? this.panelRaised,
    subtle: subtle ?? this.subtle,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    diffAdd: diffAdd ?? this.diffAdd,
    diffDelete: diffDelete ?? this.diffDelete,
    userMessageBackground: userMessageBackground ?? this.userMessageBackground,
    userMessageForeground: userMessageForeground ?? this.userMessageForeground,
    userMessageBorder: userMessageBorder ?? this.userMessageBorder,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    surfaceHighest: surfaceHighest ?? this.surfaceHighest,
    groupedBackground: groupedBackground ?? this.groupedBackground,
    inputBackground: inputBackground ?? this.inputBackground,
    inputPlaceholder: inputPlaceholder ?? this.inputPlaceholder,
    buttonPrimaryBackground:
        buttonPrimaryBackground ?? this.buttonPrimaryBackground,
    buttonPrimaryTint: buttonPrimaryTint ?? this.buttonPrimaryTint,
    buttonPrimaryDisabled: buttonPrimaryDisabled ?? this.buttonPrimaryDisabled,
  );

  @override
  PromptTokens lerp(PromptTokens? other, double t) {
    if (other == null) return this;
    return PromptTokens(
      panel: Color.lerp(panel, other.panel, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      diffAdd: Color.lerp(diffAdd, other.diffAdd, t)!,
      diffDelete: Color.lerp(diffDelete, other.diffDelete, t)!,
      userMessageBackground: Color.lerp(
        userMessageBackground,
        other.userMessageBackground,
        t,
      )!,
      userMessageForeground: Color.lerp(
        userMessageForeground,
        other.userMessageForeground,
        t,
      )!,
      userMessageBorder: Color.lerp(
        userMessageBorder,
        other.userMessageBorder,
        t,
      )!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceHighest: Color.lerp(surfaceHighest, other.surfaceHighest, t)!,
      groupedBackground: Color.lerp(
        groupedBackground,
        other.groupedBackground,
        t,
      )!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      inputPlaceholder: Color.lerp(
        inputPlaceholder,
        other.inputPlaceholder,
        t,
      )!,
      buttonPrimaryBackground: Color.lerp(
        buttonPrimaryBackground,
        other.buttonPrimaryBackground,
        t,
      )!,
      buttonPrimaryTint: Color.lerp(
        buttonPrimaryTint,
        other.buttonPrimaryTint,
        t,
      )!,
      buttonPrimaryDisabled: Color.lerp(
        buttonPrimaryDisabled,
        other.buttonPrimaryDisabled,
        t,
      )!,
    );
  }
}

/// Glyph colours for grouped settings rows.
///
/// The reference colours a settings row's leading glyph by what the row does,
/// which is what makes a long list scannable; painting them all in one brand
/// colour, as Prompt did, removes the only cue. These are its own constants
/// (`sources/theme.ts`), not new inventions: the blue it uses for primary
/// actions and radios, the green for a healthy connection, the amber for a
/// bypassed guard, the red for a destructive one.
abstract final class SettingsGlyphTones {
  /// Something to set up or open.
  static const Color action = Color(0xFF007AFF);

  /// Something protective that is currently in force.
  static const Color safe = Color(0xFF34C759);

  /// Something that relaxes a guard.
  static const Color caution = Color(0xFFFF9500);

  /// Something destructive.
  static const Color destructive = Color(0xFFFF3B30);

  /// Plain matter of fact. The reference's most common glyph colour.
  static Color neutral(ColorScheme scheme) => scheme.onSurface;
}

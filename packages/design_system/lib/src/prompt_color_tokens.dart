import 'package:flutter/material.dart';

/// Semantic colors shared by Prompt presentation features.
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
    );
  }
}

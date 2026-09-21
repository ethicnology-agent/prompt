import 'package:flutter/material.dart';

import 'prompt_color_tokens.dart';
import 'prompt_typography.dart';
import 'prompt_ui_tokens.dart';

ThemeData promptTheme() => _theme(Brightness.light);

ThemeData promptDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accent = ColorScheme.fromSeed(
    seedColor: const Color(0xff56d6b2),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff18171c),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        surface: dark ? const Color(0xff000000) : const Color(0xffffffff),
      ).copyWith(
        primary: accent.primary,
        onPrimary: accent.onPrimary,
        primaryContainer: accent.primaryContainer,
        onPrimaryContainer: accent.onPrimaryContainer,
        primaryFixed: accent.primaryFixed,
        primaryFixedDim: accent.primaryFixedDim,
        onPrimaryFixed: accent.onPrimaryFixed,
        onPrimaryFixedVariant: accent.onPrimaryFixedVariant,
        inversePrimary: accent.inversePrimary,
        secondary: accent.secondary,
        onSecondary: accent.onSecondary,
        secondaryContainer: accent.secondaryContainer,
        onSecondaryContainer: accent.onSecondaryContainer,
        secondaryFixed: accent.secondaryFixed,
        secondaryFixedDim: accent.secondaryFixedDim,
        onSecondaryFixed: accent.onSecondaryFixed,
        onSecondaryFixedVariant: accent.onSecondaryFixedVariant,
        surfaceContainerLow: dark ? const Color(0xff111111) : Colors.white,
        // Happy's `textSecondary` and `divider`, rather than a seed-derived
        // pair: every subtitle, timestamp and composer glyph reads off these.
        onSurfaceVariant: dark
            ? const Color(0xffcac4d0)
            : const Color(0xff49454f),
        outlineVariant: dark
            ? const Color(0xff2a2a2a)
            : const Color(0xffeaeaea),
      );
  final textTheme = ThemeData(brightness: brightness).textTheme
      .apply(fontFamily: promptSansFamily)
      .copyWith(
        headlineSmall: const TextStyle(
          fontSize: 24,
          height: 1.15,
          fontWeight: PromptFontWeights.semiBold,
          letterSpacing: -0.6,
        ),
        titleLarge: const TextStyle(
          fontSize: 19,
          height: 1.15,
          fontWeight: PromptFontWeights.semiBold,
          letterSpacing: -0.4,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: PromptFontWeights.semiBold,
          letterSpacing: -0.2,
        ),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.48),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
        bodySmall: const TextStyle(fontSize: 12.5, height: 1.4),
        labelLarge: const TextStyle(fontWeight: PromptFontWeights.semiBold),
      );

  final rounded = OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  final tokens = PromptTokens(
    // The reference's dark card, sampled at #161616 on its settings page.
    panel: dark ? const Color(0xff161616) : const Color(0xffffffff),
    panelRaised: dark ? const Color(0xff242426) : const Color(0xfff5f5f5),
    subtle: dark ? const Color(0xffaaaaaf) : const Color(0xff626267),
    success: dark ? const Color(0xff77d6b7) : const Color(0xff13795b),
    warning: dark ? const Color(0xffffc985) : const Color(0xff9a5600),
    danger: dark ? const Color(0xffffaaa5) : const Color(0xffb42318),
    diffAdd: dark ? const Color(0xff123d30) : const Color(0xffdcf8e9),
    diffDelete: dark ? const Color(0xff4a2225) : const Color(0xffffe5e4),
    userMessageBackground: dark
        ? const Color(0xff242426)
        : const Color(0xfff0eee6),
    userMessageForeground: dark
        ? const Color(0xfffafafa)
        : const Color(0xff18171c),
    userMessageBorder: dark ? const Color(0xff39393b) : const Color(0xffe4e4e6),
    // Happy's Android neutrals, read from `sources/theme.ts`.
    surfaceHigh: dark ? const Color(0xff1e1e1e) : const Color(0xfff8f8f8),
    surfaceHighest: dark ? const Color(0xff282828) : const Color(0xfff0f0f0),
    groupedBackground: dark ? const Color(0xff000000) : const Color(0xfff5f5f5),
    inputBackground: dark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5),
    inputPlaceholder: dark ? const Color(0xff8e8e93) : const Color(0xff999999),
    buttonPrimaryBackground: dark
        ? const Color(0xfff5f5f5)
        : const Color(0xff000000),
    buttonPrimaryTint: dark ? const Color(0xff111111) : const Color(0xffffffff),
    buttonPrimaryDisabled: const Color(0xffc0c0c0),
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    extensions: [tokens],
    useMaterial3: true,
    fontFamily: promptSansFamily,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff1c1c1e) : const Color(0xfff5f5f5),
      border: rounded,
      enabledBorder: rounded,
      focusedBorder: rounded.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiTokens.cardRadius),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    // The reference's primary call to action is black, tinted white, and fully
    // rounded — a pill, not a rounded rectangle. Measured on its `Troubleshoot`
    // button: 131 px tall with a 65.5 px corner, which only a half-height
    // radius fits.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: tokens.buttonPrimaryBackground,
        foregroundColor: tokens.buttonPrimaryTint,
        disabledBackgroundColor: tokens.buttonPrimaryDisabled,
        disabledForegroundColor: tokens.buttonPrimaryTint,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: PromptFontWeights.semiBold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.onSurface,
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiTokens.controlRadius),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiTokens.controlRadius),
      ),
      backgroundColor: dark ? const Color(0xff252d34) : const Color(0xff20272c),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: dark ? const Color(0xff1c1c1e) : Colors.white,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: dark ? const Color(0xff1c1c1e) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  final light = promptTheme();
  final dark = promptDarkTheme();
  final lightTokens = light.extension<PromptTokens>()!;
  final darkTokens = dark.extension<PromptTokens>()!;

  test('the neutral ramp matches the reference in both appearances', () {
    // Sampled from the reference on a Pixel 6a, and read from its `theme.ts`.
    expect(lightTokens.groupedBackground, const Color(0xfff5f5f5));
    expect(darkTokens.groupedBackground, const Color(0xff000000));
    expect(lightTokens.surfaceHigh, const Color(0xfff8f8f8));
    expect(darkTokens.surfaceHigh, const Color(0xff1e1e1e));
    expect(lightTokens.surfaceHighest, const Color(0xfff0f0f0));
    expect(darkTokens.surfaceHighest, const Color(0xff282828));
    expect(light.colorScheme.onSurfaceVariant, const Color(0xff49454f));
    expect(dark.colorScheme.onSurfaceVariant, const Color(0xffcac4d0));
    expect(light.colorScheme.outlineVariant, const Color(0xffeaeaea));
    expect(dark.colorScheme.outlineVariant, const Color(0xff2a2a2a));
  });

  test('the primary call to action inverts rather than staying black', () {
    // `RoundButton.tsx`: black on white text in light, near-white on near-black
    // in dark. A black button on the black dark page would be invisible.
    expect(lightTokens.buttonPrimaryBackground, const Color(0xff000000));
    expect(lightTokens.buttonPrimaryTint, const Color(0xffffffff));
    expect(darkTokens.buttonPrimaryBackground, const Color(0xfff5f5f5));
    expect(darkTokens.buttonPrimaryTint, const Color(0xff111111));
  });

  test('every pairing this pass fixed stays legible in both appearances', () {
    for (final (name, background, foreground) in [
      (
        'primary button light',
        lightTokens.buttonPrimaryBackground,
        lightTokens.buttonPrimaryTint,
      ),
      (
        'primary button dark',
        darkTokens.buttonPrimaryBackground,
        darkTokens.buttonPrimaryTint,
      ),
      (
        'composer action light',
        lightTokens.surfaceHighest,
        light.colorScheme.onSurfaceVariant,
      ),
      (
        'composer action dark',
        darkTokens.surfaceHighest,
        dark.colorScheme.onSurfaceVariant,
      ),
      ('grouped card light', lightTokens.panel, light.colorScheme.onSurface),
      ('grouped card dark', darkTokens.panel, dark.colorScheme.onSurface),
      (
        'section heading light',
        lightTokens.groupedBackground,
        light.colorScheme.onSurfaceVariant,
      ),
      (
        'section heading dark',
        darkTokens.groupedBackground,
        dark.colorScheme.onSurfaceVariant,
      ),
    ]) {
      expect(
        contrast(background, foreground),
        greaterThanOrEqualTo(4.5),
        reason: '$name falls under 4.5:1',
      );
    }
  });

  test('the grouped card matches the reference in both appearances', () {
    expect(lightTokens.panel, const Color(0xffffffff));
    expect(darkTokens.panel, const Color(0xff161616));
  });

  test('a card is distinguishable from the page it sits on', () {
    for (final (name, page, card) in [
      ('light', lightTokens.groupedBackground, lightTokens.panel),
      ('dark', darkTokens.groupedBackground, darkTokens.panel),
    ]) {
      expect(
        page,
        isNot(card),
        reason: 'the $name card vanishes into its page',
      );
    }
  });
}

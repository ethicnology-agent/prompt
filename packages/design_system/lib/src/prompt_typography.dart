/// Typefaces shared by every Prompt surface.
///
/// Happy renders its whole interface in IBM Plex Sans and its code in IBM Plex
/// Mono (`packages/happy-app/sources/constants/Typography.ts`). Prompt shipped
/// no font at all, so every screen fell back to Roboto and no amount of layout
/// work could make the two read alike. The families below ship inside this
/// package so the application and the component catalog both pick them up.
///
/// Only the 400 and 600 weights exist. Asking for a heavier weight makes the
/// engine synthesise one, which thickens strokes unevenly; use
/// [PromptFontWeights.semiBold] for emphasis instead of `w700`.
library;

import 'package:flutter/material.dart';

/// Body and interface typeface.
const String promptSansFamily = 'packages/design_system/IBMPlexSans';

/// Monospaced typeface, for code, diffs, paths and shell commands.
const String promptMonoFamily = 'packages/design_system/IBMPlexMono';

/// The weights actually bundled, to keep call sites from asking for a weight
/// that would have to be synthesised.
abstract final class PromptFontWeights {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight semiBold = FontWeight.w600;
}

import 'package:flutter/material.dart';

/// How loudly a notice speaks.
enum NoticeTone {
  /// Something the user should know before they act.
  warning,

  /// Something that has already gone wrong.
  error,
}

/// A bordered note that sets itself apart from the prose around it.
///
/// The reference keeps dedicated tokens for exactly this — `box.warning` and
/// `box.error` in `sources/theme.ts` — a tinted fill, a saturated border and
/// text in the border's colour. Prompt was writing the same warnings as
/// ordinary paragraphs, so a caveat about an experimental surface read like
/// body copy and was skipped.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    required this.message,
    this.tone = NoticeTone.warning,
    super.key,
  });

  final String message;
  final NoticeTone tone;

  /// Fill, border and text for each tone, in both appearances.
  ///
  /// Dark uses the reference's translucent fills rather than a solid tint, so
  /// the box sits on whatever surface it lands on.
  ///
  /// One departure, measured rather than guessed: the reference writes its
  /// light warning in `#FF9500` on `#FFF8F0`, which is 2.09:1 — under half the
  /// 4.5:1 a body-sized message needs. The fill and the border keep the
  /// reference's colours, so the box looks the same; only the text is darkened,
  /// to 5.38:1. Its light error text is `#FF3B30`, which clears the bar, and is
  /// left alone.
  static ({Color background, Color border, Color text}) _palette(
    NoticeTone tone,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    return switch (tone) {
      NoticeTone.warning => (
        background: dark ? const Color(0x26ff9f0a) : const Color(0xfffff8f0),
        border: dark ? const Color(0xffff9f0a) : const Color(0xffff9500),
        text: dark ? const Color(0xffffab00) : const Color(0xff9a5600),
      ),
      NoticeTone.error => (
        background: dark ? const Color(0x26ff453a) : const Color(0xfffff0f0),
        border: dark ? const Color(0xffff453a) : const Color(0xffff3b30),
        text: dark ? const Color(0xffff6b6b) : const Color(0xffff3b30),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _palette(tone, theme.brightness);
    return Semantics(
      container: true,
      liveRegion: tone == NoticeTone.error,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 20 / 14,
            color: palette.text,
          ),
        ),
      ),
    );
  }
}

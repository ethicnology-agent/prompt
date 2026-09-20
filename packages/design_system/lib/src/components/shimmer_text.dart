import 'package:flutter/material.dart';

/// One sweep across the text.
const Duration _sweepDuration = Duration(milliseconds: 1700);

/// The still moment between two sweeps.
const Duration _sweepPause = Duration(milliseconds: 650);

/// A quiet, text-clipped progress sweep.
///
/// A session that is producing a turn says so by sweeping its own title rather
/// than by adding a spinner or a status word, which keeps the row to three
/// lines and leaves the top-right slot free for something the user must act on.
///
/// Timings, band width and gradient match Happy's `ShimmerText`
/// (`sources/components/ShimmerText.tsx`): a 1700 ms linear sweep followed by a
/// 650 ms pause, with a band 40% of the text width and never under 44 logical
/// pixels.
///
/// When the platform asks for reduced motion the sweep is dropped and the text
/// is drawn flat in [baseColor], as Happy does.
class ShimmerText extends StatefulWidget {
  const ShimmerText({
    required this.text,
    required this.baseColor,
    required this.highlightColor,
    this.style,
    super.key,
  });

  final String text;
  final Color baseColor;
  final Color highlightColor;
  final TextStyle? style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _sweepDuration + _sweepPause,
  );

  /// The fraction of the cycle spent sweeping; the remainder is the pause.
  static final double _sweepFraction =
      _sweepDuration.inMilliseconds /
      (_sweepDuration.inMilliseconds + _sweepPause.inMilliseconds);

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? const TextStyle()).copyWith(
      color: widget.baseColor,
    );
    final flat = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (MediaQuery.disableAnimationsOf(context)) return flat;

    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => _sweepShader(bounds),
            child: child,
          ),
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Shader _sweepShader(Rect bounds) {
    final width = bounds.width;
    final band = (width * 0.4).clamp(44.0, double.infinity);
    // Hold the band off the right edge for the pause, exactly as the reference
    // does by clamping its interpolation past the sweep fraction.
    final progress = (_controller.value / _sweepFraction).clamp(0.0, 1.0);
    final start = -band + (width + band) * progress;
    return LinearGradient(
      colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
      stops: const [0, 0.5, 1],
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ).createShader(Rect.fromLTWH(start, bounds.top, band, bounds.height));
  }
}

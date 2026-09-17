import 'package:flutter/material.dart';

/// An icon that turns while [spinning] and is still otherwise.
///
/// The motion is ambient; what carries the signal is its stopping, so a run
/// that ends is noticed without a notification. Rotation follows the direction
/// the arrows of a cyclic glyph point, which is anticlockwise for the Material
/// sync and replay icons.
///
/// The controller only runs while spinning, so an idle icon costs no frames,
/// and it stays still when the platform asks for reduced motion.
class SpinningIcon extends StatefulWidget {
  const SpinningIcon({
    required this.icon,
    required this.spinning,
    this.size,
    this.color,
    super.key,
  });

  final IconData icon;
  final bool spinning;
  final double? size;
  final Color? color;

  /// One full turn, slow enough to read as deliberate rather than frantic.
  static const period = Duration(milliseconds: 1200);

  @override
  State<SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: SpinningIcon.period,
    vsync: this,
  );
  late final Animation<double> _turns = Tween<double>(
    begin: 0,
    end: -1,
  ).animate(_controller);

  void _sync() {
    final shouldSpin =
        widget.spinning && !MediaQuery.disableAnimationsOf(context);
    if (shouldSpin) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SpinningIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spinning != widget.spinning) _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns,
    child: Icon(widget.icon, size: widget.size, color: widget.color),
  );
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A controlled chooser that floats above its child without changing its layout.
///
/// [popupBuilder] receives the available total height, including its header.
/// Its content should shrink-wrap short lists and scroll within this bound.
class AnchoredChoiceOverlay extends StatefulWidget {
  const AnchoredChoiceOverlay({
    super.key,
    required this.child,
    required this.open,
    required this.onDismiss,
    required this.popupBuilder,
    this.maxWidth = 560,
  }) : assert(maxWidth > 0);

  final Widget child;
  final bool open;
  final VoidCallback onDismiss;
  final Widget Function(BuildContext context, double maxHeight) popupBuilder;
  final double maxWidth;

  @override
  State<AnchoredChoiceOverlay> createState() => _AnchoredChoiceOverlayState();
}

class _AnchoredChoiceOverlayState extends State<AnchoredChoiceOverlay>
    with WidgetsBindingObserver {
  final _controller = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKey);
    if (widget.open) _controller.show();
  }

  @override
  void didUpdateWidget(AnchoredChoiceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.open) {
          _controller.show();
        } else {
          _controller.hide();
        }
      });
    }
  }

  void _dismiss() {
    if (mounted && widget.open) widget.onDismiss();
  }

  bool _handleKey(KeyEvent event) {
    if (widget.open &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return true;
    }
    return false;
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Register for metrics updates even when Scaffold has removed the keyboard
    // inset from the MediaQuery inherited by its resized body.
    MediaQuery.of(context);
    final metrics = MediaQueryData.fromView(View.of(context));
    return PopScope<Object?>(
      canPop: !widget.open,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _dismiss();
      },
      child: TextFieldTapRegion(
        child: OverlayPortal.overlayChildLayoutBuilder(
          controller: _controller,
          overlayLocation: OverlayChildLocation.rootOverlay,
          overlayChildBuilder: (context, info) =>
              _buildPopup(context, info, metrics),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildPopup(
    BuildContext context,
    OverlayChildLayoutInfo info,
    MediaQueryData metrics,
  ) {
    final anchor = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final size = info.overlaySize;
    final left = metrics.viewPadding.left + 16;
    final right = math.max(left, size.width - metrics.viewPadding.right - 16);
    final top = metrics.viewPadding.top + 16;
    final bottom = math.max(
      top,
      math.min(size.height, metrics.size.height - metrics.viewInsets.bottom) -
          (metrics.viewInsets.bottom > 0 ? 0 : metrics.viewPadding.bottom) -
          16,
    );
    final width = math.min(
      math.min(widget.maxWidth, anchor.width),
      right - left,
    );
    final x = anchor.left.clamp(left, math.max(left, right - width)).toDouble();
    final above = math.max(0.0, math.min(anchor.top - 8, bottom) - top);
    // When the composer leaves almost no space, use the readable viewport.
    // The popup may cover part of the composer, but never pushes its layout.
    final popupBottom = above >= 96 ? math.min(anchor.top - 8, bottom) : bottom;
    final maxHeight = math.min(400.0, math.max(0.0, popupBottom - top));
    final hole = Rect.fromLTRB(
      anchor.left.clamp(0.0, size.width).toDouble(),
      anchor.top.clamp(0.0, size.height).toDouble(),
      anchor.right.clamp(0.0, size.width).toDouble(),
      anchor.bottom.clamp(0.0, size.height).toDouble(),
    );

    Widget barrier(Rect rect) => Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: const SizedBox.expand(),
      ),
    );

    return TextFieldTapRegion(
      child: Stack(
        children: [
          // Leave the anchor interactive, so its chips can switch or close the
          // active chooser. All other background taps are consumed.
          barrier(Rect.fromLTRB(0, 0, size.width, hole.top)),
          barrier(Rect.fromLTRB(0, hole.bottom, size.width, size.height)),
          barrier(Rect.fromLTRB(0, hole.top, hole.left, hole.bottom)),
          barrier(Rect.fromLTRB(hole.right, hole.top, size.width, hole.bottom)),
          Positioned(
            left: x,
            bottom: size.height - popupBottom,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: widget.popupBuilder(context, maxHeight),
            ),
          ),
        ],
      ),
    );
  }
}

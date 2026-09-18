import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'app_button.dart';
import 'attachment_thumbnail.dart';

/// No image provider/cache, file, URL, or encoded-buffer ownership. The
/// controller owns this route's decoded pixels and is disposed on dismissal.
Future<void> showAttachmentImageViewer(
  BuildContext context, {
  required AttachmentThumbnailController controller,
  required String label,
}) async {
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            AttachmentImageViewer(controller: controller, label: label),
      ),
    );
  } finally {
    controller.dispose();
  }
}

class AttachmentImageViewer extends StatefulWidget {
  const AttachmentImageViewer({
    required this.controller,
    required this.label,
    super.key,
  });
  final AttachmentThumbnailController controller;
  final String label;
  @override
  State<AttachmentImageViewer> createState() => _AttachmentImageViewerState();
}

class _AttachmentImageViewerState extends State<AttachmentImageViewer> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    // A source can be invalidated while its underlying transcript rebuilds.
    // Pixels are already gone; defer only the viewer's placeholder rebuild.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    widget.controller.removeListener(_changed);
    widget.controller.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      8.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (1 - scale) * _viewport.width / 2,
        (1 - scale) * _viewport.height / 2,
        0,
      );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: AppIconButton(
            icon: Icons.close,
            tooltip: 'Close image',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: Builder(
            builder: (context) {
              if (widget.controller.state != AttachmentThumbnailState.ready) {
                return Center(
                  child: Text(switch (widget.controller.state) {
                    AttachmentThumbnailState.loading => 'Loading image',
                    AttachmentThumbnailState.cleared =>
                      'Image cleared for privacy. Close and reopen to inspect.',
                    _ => 'Image unavailable',
                  }),
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _viewport = constraints.biggest;
                        return InteractiveViewer(
                          transformationController: _transform,
                          minScale: 1,
                          maxScale: 8,
                          child: Semantics(
                            image: true,
                            label: widget.label,
                            child: CustomPaint(
                              size: constraints.biggest,
                              painter: _ViewerPainter(widget.controller),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIconButton(
                        icon: Icons.zoom_out,
                        tooltip: 'Zoom out',
                        onPressed: () => _zoom(.5),
                      ),
                      AppIconButton(
                        icon: Icons.center_focus_strong,
                        tooltip: 'Reset zoom',
                        onPressed: () => _transform.value = Matrix4.identity(),
                      ),
                      AppIconButton(
                        icon: Icons.zoom_in,
                        tooltip: 'Zoom in',
                        onPressed: () => _zoom(2),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ViewerPainter extends CustomPainter {
  _ViewerPainter(this.controller) : super(repaint: controller);
  final AttachmentThumbnailController controller;
  @override
  void paint(Canvas canvas, Size size) => controller.paint(canvas, size);
  @override
  bool shouldRepaint(_ViewerPainter oldDelegate) =>
      oldDelegate.controller != controller;
}

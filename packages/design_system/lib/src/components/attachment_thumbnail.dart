import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_button.dart';

enum AttachmentThumbnailState { loading, ready, unavailable, cleared }

/// Owns decoded pixels only. The caller retains ownership of encoded bytes.
/// Clearing invalidates pending work; late results are disposed, never cached.
class AttachmentThumbnailController extends ChangeNotifier
    with WidgetsBindingObserver {
  /// A bounded inspection bitmap, distinct from the 192px thumbnail. Encoded
  /// bytes remain owned by the caller and are not retained after decoding.
  factory AttachmentThumbnailController.viewer(Uint8List bytes) =>
      AttachmentThumbnailController(
        bytes,
        decoder: (data) => _decodeThumbnail(data, maxDimension: 2048),
      );
  AttachmentThumbnailController(
    Uint8List bytes, {
    @visibleForTesting Future<ui.Image> Function(Uint8List)? decoder,
  }) {
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _state = AttachmentThumbnailState.cleared;
    } else {
      _load(bytes, decoder ?? _decodeThumbnail);
    }
  }

  AttachmentThumbnailState _state = AttachmentThumbnailState.loading;
  AttachmentThumbnailState get state => _state;
  ui.Image? _image;
  int _generation = 0;
  bool _disposed = false;

  @visibleForTesting
  ui.Image? get debugImage => _image;

  void paint(Canvas canvas, Size size, {BoxFit fit = BoxFit.contain}) {
    final image = _image;
    if (image == null) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: fit,
    );
  }

  Future<void> _load(
    Uint8List bytes,
    Future<ui.Image> Function(Uint8List) decode,
  ) async {
    final generation = _generation;
    try {
      final image = await decode(bytes);
      if (_disposed || generation != _generation) {
        image.dispose();
        return;
      }
      _image = image;
      _state = AttachmentThumbnailState.ready;
      notifyListeners();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _state = AttachmentThumbnailState.unavailable;
      notifyListeners();
    }
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    final image = _image;
    _image = null;
    image?.dispose();
    _state = AttachmentThumbnailState.cleared;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final image = _image;
    _image = null;
    image?.dispose();
    _state = AttachmentThumbnailState.cleared;
    _disposed = true;
    super.dispose();
  }
}

Future<ui.Image> _decodeThumbnail(
  Uint8List bytes, {
  int maxDimension = 192,
}) async {
  if (bytes.lengthInBytes > 10 * 1024 * 1024) {
    throw const FormatException('Image exceeds preview byte limit.');
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // Bound decompressed input dimensions as well as the displayed thumbnail.
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width > 16384 ||
        descriptor.height > 16384 ||
        descriptor.width * descriptor.height > 40000000) {
      throw const FormatException('Image dimensions exceed preview limits.');
    }
    final largest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = largest > maxDimension ? maxDimension / largest : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round().clamp(1, maxDimension),
      targetHeight: (descriptor.height * scale).round().clamp(1, maxDimension),
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

class AttachmentThumbnail extends StatefulWidget {
  const AttachmentThumbnail({
    super.key,
    required this.controller,
    required this.label,
    this.onRemove,
    this.onOpen,
  });
  final AttachmentThumbnailController controller;
  final String label;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;

  @override
  State<AttachmentThumbnail> createState() => _AttachmentThumbnailWidgetState();
}

class _AttachmentThumbnailWidgetState extends State<AttachmentThumbnail> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AttachmentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.clear();
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final status = switch (state) {
      AttachmentThumbnailState.loading => 'Loading preview',
      AttachmentThumbnailState.ready => 'Image preview',
      AttachmentThumbnailState.unavailable => 'Preview unavailable',
      AttachmentThumbnailState.cleared => 'Preview cleared',
    };
    return SizedBox(
      width: 88,
      height: 80,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            width: 64,
            height: 64,
            child: Semantics(
              label: '${widget.label}, $status',
              button: widget.onOpen != null,
              image: state == AttachmentThumbnailState.ready,
              child: InkWell(
                onTap: state == AttachmentThumbnailState.ready
                    ? widget.onOpen
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: state == AttachmentThumbnailState.ready
                        ? CustomPaint(
                            painter: _ThumbnailPainter(widget.controller),
                          )
                        : Icon(
                            state == AttachmentThumbnailState.loading
                                ? Icons.image_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.onRemove != null)
            Positioned(
              right: 0,
              top: 0,
              child: AppIconButton(
                icon: Icons.close,
                tooltip: 'Remove ${widget.label}',
                onPressed: () {
                  widget.controller.clear();
                  widget.onRemove?.call();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.controller) : super(repaint: controller);
  final AttachmentThumbnailController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final image = controller._image;
    if (image == null) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.cover,
    );
  }

  @override
  bool shouldRepaint(_ThumbnailPainter oldDelegate) =>
      oldDelegate.controller != controller;
}

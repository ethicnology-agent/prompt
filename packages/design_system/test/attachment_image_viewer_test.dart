import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ui.Image bitmap([int width = 4]) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, 4);
  picture.dispose();
  return image;
}

Future<void> settled(AttachmentThumbnailController controller) async {
  if (controller.state != AttachmentThumbnailState.loading) return;
  final done = Completer<void>();
  void changed() {
    if (!done.isCompleted) done.complete();
  }

  controller.addListener(changed);
  await done.future;
  controller.removeListener(changed);
}

void main() {
  testWidgets(
    'inspection decodes beyond thumbnail resolution, zooms and closes without cache or source mutation',
    (tester) async {
      final cache = PaintingBinding.instance.imageCache;
      final count = cache.currentSize;
      late Uint8List bytes;
      late AttachmentThumbnailController controller;
      await tester.runAsync(() async {
        final image = bitmap(3000);
        bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        controller = AttachmentThumbnailController.viewer(bytes);
        await settled(controller);
      });
      final original = bytes.toList();
      final decoded = controller.debugImage!;
      expect(decoded.width, 2048);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAttachmentImageViewer(
                  context,
                  controller: controller,
                  label: 'Local image',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      expect(transform.value.getMaxScaleOnAxis(), 2);
      final beforePan = transform.value.entry(0, 3);
      await tester.drag(find.byType(InteractiveViewer), const Offset(30, 20));
      await tester.pumpAndSettle();
      expect(transform.value.entry(0, 3), isNot(beforePan));
      await tester.tap(find.byTooltip('Reset zoom'));
      expect(transform.value.getMaxScaleOnAxis(), 1);
      await tester.tap(find.byTooltip('Close image'));
      await tester.pumpAndSettle();
      expect(decoded.debugDisposed, isTrue);
      expect(bytes, original);
      expect(cache.currentSize, count);
    },
  );

  testWidgets(
    'inactivity during decode clears viewer and destroys late pixels; back remains available',
    (tester) async {
      final result = Completer<ui.Image>();
      final controller = AttachmentThumbnailController(
        Uint8List(0),
        decoder: (_) => result.future,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAttachmentImageViewer(
                  context,
                  controller: controller,
                  label: 'Private image',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final image = bitmap();
      result.complete(image);
      await tester.pump();
      expect(image.debugDisposed, isTrue);
      expect(controller.debugImage, isNull);
      expect(find.textContaining('Image cleared for privacy'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentImageViewer), findsNothing);
    },
  );
}

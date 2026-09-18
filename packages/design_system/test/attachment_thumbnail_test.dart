import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ui.Image bitmap() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = Colors.teal,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
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
    'real local PNG decodes without image providers or global cache',
    (tester) async {
      final cache = PaintingBinding.instance.imageCache;
      final cached = cache.currentSize;
      final live = cache.liveImageCount;
      late AttachmentThumbnailController controller;
      await tester.runAsync(() async {
        final source = bitmap();
        final data = await source.toByteData(format: ui.ImageByteFormat.png);
        source.dispose();
        controller = AttachmentThumbnailController(data!.buffer.asUint8List());
        await settled(controller);
      });
      expect(controller.state, AttachmentThumbnailState.ready);
      expect(controller.debugImage!.width, 4);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentThumbnail(
              controller: controller,
              label: 'Local picture',
              onRemove: () {},
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      expect(cache.currentSize, cached);
      expect(cache.liveImageCount, live);
      final image = controller.debugImage!;
      await tester.pumpWidget(const SizedBox());
      expect(controller.state, AttachmentThumbnailState.cleared);
      expect(image.debugDisposed, isTrue);
      controller.dispose();
    },
  );

  testWidgets('removal clears pixels before invoking callback', (tester) async {
    final image = bitmap();
    final controller = AttachmentThumbnailController(
      Uint8List(0),
      decoder: (_) async => image,
    );
    await tester.pump();
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentThumbnail(
            controller: controller,
            label: 'Attachment',
            onRemove: () {
              expect(image.debugDisposed, isTrue);
              expect(controller.debugImage, isNull);
              removed = true;
            },
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppIconButton)), const Size(48, 48));
    await tester.tap(find.byTooltip('Remove Attachment'));
    expect(removed, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final dispose in [false, true]) {
    testWidgets(
      'late decode cannot restore pixels after ${dispose ? 'dispose' : 'clear'}',
      (tester) async {
        final result = Completer<ui.Image>();
        final controller = AttachmentThumbnailController(
          Uint8List(0),
          decoder: (_) => result.future,
        );
        if (dispose) {
          controller.dispose();
        } else {
          controller.clear();
        }
        final image = bitmap();
        result.complete(image);
        await tester.pump();
        expect(image.debugDisposed, isTrue);
        expect(controller.debugImage, isNull);
        if (!dispose) controller.dispose();
      },
    );
  }

  testWidgets('lifecycle clears decoded pixels synchronously without a frame', (
    tester,
  ) async {
    final image = bitmap();
    final controller = AttachmentThumbnailController(
      Uint8List(0),
      decoder: (_) async => image,
    );
    await tester.pump();
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(image.debugDisposed, isTrue);
    expect(controller.debugImage, isNull);
    expect(controller.state, AttachmentThumbnailState.cleared);
    controller.dispose();
  });

  testWidgets('invalid image shows only generic unavailable state', (
    tester,
  ) async {
    late AttachmentThumbnailController controller;
    await tester.runAsync(() async {
      controller = AttachmentThumbnailController(Uint8List.fromList([1, 2, 3]));
      await settled(controller);
    });
    expect(controller.state, AttachmentThumbnailState.unavailable);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentThumbnail(
            controller: controller,
            label: 'Unreadable file',
            onRemove: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/presentation/widgets/composer.dart';

Future<Uint8List> png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<void> decoded(WidgetTester tester) async {
  final controllers = tester
      .widgetList<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
      .map((widget) => widget.controller)
      .toList();
  await tester.runAsync(() async {
    for (final controller in controllers) {
      if (controller.state != AttachmentThumbnailState.loading) continue;
      final done = Completer<void>();
      void changed() {
        if (!done.isCompleted) done.complete();
      }

      controller.addListener(changed);
      await done.future;
      controller.removeListener(changed);
    }
  });
  await tester.pump();
}

void main() {
  late ValueNotifier<List<PromptAttachment>> attachments;
  late TextEditingController text;
  late List<PromptAttachment> removed;
  setUp(() {
    attachments = ValueNotifier([]);
    text = TextEditingController();
    removed = [];
  });
  tearDown(() {
    for (final attachment in attachments.value) {
      attachment.release();
    }
    attachments.dispose();
    text.dispose();
  });

  testWidgets(
    'selected image opens viewer without releasing bytes and removal invalidates it',
    (tester) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await png();
      });
      final attachment = PromptAttachment(name: 'inspect.png', bytes: bytes);
      attachments.value = [attachment];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttachmentStrip(attachments: attachments)),
        ),
      );
      await decoded(tester);
      final thumbnail = tester.widget<AttachmentThumbnail>(
        find.byType(AttachmentThumbnail),
      );
      expect(thumbnail.onOpen, isNotNull);
      thumbnail.onOpen!();
      await tester.pumpAndSettle();
      final viewer = tester.widget<AttachmentImageViewer>(
        find.byType(AttachmentImageViewer),
      );
      expect(attachment.isReleased, isFalse);
      attachment.release();
      attachments.value = [];
      await tester.pump();
      expect(viewer.controller.state, AttachmentThumbnailState.cleared);
      expect(viewer.controller.debugImage, isNull);
      await tester.tap(find.byTooltip('Close image'));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentImageViewer), findsNothing);
    },
  );

  Future<void> mount(
    WidgetTester tester, {
    double textScale = 2,
    double width = 320,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: promptTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SizedBox(
            width: width,
            child: Composer(
              controller: text,
              command: null,
              attachments: attachments,
              onRemoveAttachment: (attachment) {
                removed.add(attachment);
                attachment.release();
                attachments.value = attachments.value
                    .where((item) => !identical(item, attachment))
                    .toList();
              },
              onSubmit: () async {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('empty composer uses one accessible input row', (tester) async {
    await mount(tester, textScale: 1, width: 400);
    final height = tester.getSize(find.byType(Composer)).height;
    expect(height, greaterThanOrEqualTo(48));
    expect(height, lessThanOrEqualTo(56));
    await tester.enterText(
      find.byType(TextField),
      'First line\nSecond line\nThird line',
    );
    await tester.pump();
    expect(tester.getSize(find.byType(Composer)).height, greaterThan(height));
    expect(text.text, 'First line\nSecond line\nThird line');
    expect(tester.takeException(), isNull);
  });

  for (final released in [false, true]) {
    testWidgets(
      'picker result arriving inactive resumes only while owner retains bytes released=$released',
      (tester) async {
        final bytes = (await tester.runAsync(png))!;
        await mount(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final attachment = PromptAttachment(name: 'picker.png', bytes: bytes);
        attachments.value = [attachment];
        await tester.pump();
        final initial = tester
            .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
            .controller;
        expect(initial.state, AttachmentThumbnailState.cleared);
        expect(initial.debugImage, isNull);
        if (released) attachment.release();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        if (released) {
          expect(find.byType(AttachmentThumbnail), findsNothing);
        } else {
          await decoded(tester);
          final resumed = tester
              .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
              .controller;
          expect(resumed.state, AttachmentThumbnailState.ready);
          expect(resumed.debugImage, isNotNull);
          expect(initial.debugImage, isNull);
          expect(attachment.isReleased, isFalse);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'five image previews stay in one bounded strip and remove through owner',
    (tester) async {
      final bytes = (await tester.runAsync(png))!;
      attachments.value = List.generate(
        5,
        (index) => PromptAttachment(
          name: 'Image $index.png',
          bytes: Uint8List.fromList(bytes),
        ),
      );
      await mount(tester);
      await decoded(tester);
      expect(find.byType(AttachmentThumbnail), findsNWidgets(5));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('composer-attachments')))
            .height,
        80,
      );
      final first = attachments.value.first;
      final image = tester
          .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail).first)
          .controller
          .debugImage!;
      await tester.tap(find.byTooltip('Remove Image 0.png'));
      expect(removed, [first]);
      expect(first.isReleased, isTrue);
      expect(image.debugDisposed, isTrue);
      await tester.pump();
      expect(find.byType(AttachmentThumbnail), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same filename replacement invalidates prior controller before a frame',
    (tester) async {
      final bytes = (await tester.runAsync(png))!;
      final original = PromptAttachment(
        name: 'same.png',
        bytes: Uint8List.fromList(bytes),
      );
      attachments.value = [original];
      await mount(tester);
      await decoded(tester);
      final oldController = tester
          .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
          .controller;
      final oldImage = oldController.debugImage!;
      final replacement = PromptAttachment(
        name: 'same.png',
        bytes: Uint8List.fromList(bytes),
      );
      original.release();
      attachments.value = [replacement];
      expect(oldImage.debugDisposed, isTrue);
      expect(oldController.debugImage, isNull);
      await tester.pump();
      await decoded(tester);
      final current = tester
          .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
          .controller;
      expect(identical(current, oldController), isFalse);
      final currentImage = current.debugImage!;
      attachments.value = [];
      expect(currentImage.debugDisposed, isTrue);
      replacement.release();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('non-images retain filename size and removable chip', (
    tester,
  ) async {
    attachments.value = [
      PromptAttachment(name: 'notes.txt', bytes: Uint8List.fromList([1, 2, 3])),
    ];
    await mount(tester);
    expect(find.byType(AttachmentThumbnail), findsNothing);
    expect(find.textContaining('notes.txt'), findsOneWidget);
    expect(find.textContaining('3 B'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove attachment'));
    expect(removed, hasLength(1));
    expect(attachments.value, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unmount releases a ready preview but leaves attachment ownership intact',
    (tester) async {
      final bytes = (await tester.runAsync(png))!;
      final attachment = PromptAttachment(name: 'local.png', bytes: bytes);
      attachments.value = [attachment];
      await mount(tester);
      await decoded(tester);
      final controller = tester
          .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
          .controller;
      final image = controller.debugImage!;
      await tester.pumpWidget(const SizedBox());
      expect(image.debugDisposed, isTrue);
      expect(controller.debugImage, isNull);
      expect(attachment.isReleased, isFalse);
      expect(removed, isEmpty);
    },
  );

  testWidgets(
    'lifecycle and unmount release pixels without retaining encoded bytes',
    (tester) async {
      final bytes = (await tester.runAsync(png))!;
      final attachment = PromptAttachment(name: 'local.png', bytes: bytes);
      final ownedBytes = attachment.bytes;
      attachments.value = [attachment];
      await mount(tester);
      await decoded(tester);
      final controller = tester
          .widget<AttachmentThumbnail>(find.byType(AttachmentThumbnail))
          .controller;
      final image = controller.debugImage!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(image.debugDisposed, isTrue);
      expect(controller.debugImage, isNull);
      attachment.release();
      attachments.value = [];
      expect(ownedBytes.every((byte) => byte == 0), isTrue);
      expect(attachment.isReleased, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

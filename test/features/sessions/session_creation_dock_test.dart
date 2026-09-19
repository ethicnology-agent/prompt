import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/capabilities/capabilities.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/chat/chat.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/sessions/presentation/session_creation_dock.dart';
import 'package:prompt/features/sessions/presentation/worktree_picker.dart';

void main() {
  testWidgets(
    'machine chooser applies immediately and preserves composer and draft',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = TextEditingController(text: 'Prepared draft');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 393,
                child: SessionCreationDock(
                  profile: fixture.profile,
                  viewModel: fixture.model,
                  controller: controller,
                  focusNode: focus,
                  onLaunch: (_) {},
                  onExpandedChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final machine = find.byWidgetPredicate(
        (widget) =>
            widget is CreationConfigurationRow && widget.label == 'Machine',
      );
      await tester.ensureVisible(machine);
      final bounds = tester.getRect(find.byType(TextField));
      await tester.tap(machine);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Apply'), findsNothing);
      expect(tester.getRect(find.byType(TextField)), bounds);
      expect(focus.hasFocus, isTrue);
      final card = find.byType(InlineSelectionPanel<String>);
      expect(
        tester.widget<InlineSelectionPanel<String>>(card).selected,
        fixture.profile.id,
      );
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.text(fixture.profile.displayOrigin),
        ),
      );
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(machine, findsOneWidget);
      await tester.tap(machine);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(focus.hasFocus, isTrue);
      expect(controller.text, 'Prepared draft');
      expect(fixture.created, isEmpty);
    },
  );

  testWidgets(
    'worktree choices float and creating requires an explicit form action',
    (tester) async {
      final fixture = _Fixture(worktrees: true);
      addTearDown(fixture.dispose);
      final controller = TextEditingController(text: 'Prepared worktree draft');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 393,
                child: SessionCreationDock(
                  profile: fixture.profile,
                  viewModel: fixture.model,
                  controller: controller,
                  focusNode: focus,
                  onLaunch: (_) {},
                  onExpandedChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final worktree = find.byWidgetPredicate(
        (widget) =>
            widget is CreationConfigurationRow && widget.label == 'Worktree',
      );
      await tester.ensureVisible(worktree);
      final composer = tester.getRect(find.byType(TextField));
      await tester.tap(worktree);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(WorktreePicker), findsNothing);
      expect(tester.getRect(find.byType(TextField)), composer);
      expect(focus.hasFocus, isTrue);
      final selected = find.byWidgetPredicate(
        (widget) => widget is ListTile && widget.selected,
      );
      expect(selected, findsOneWidget);
      expect(
        find.descendant(of: selected, matching: find.text('main')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      final card = find.byType(InlineSelectionPanel<Object>);
      await tester.tap(find.text('Refresh worktrees'));
      await tester.pumpAndSettle();
      expect(fixture.worktreeLoads, 2);
      await tester.tap(find.descendant(of: card, matching: find.text('topic')));
      await tester.pumpAndSettle();
      expect(fixture.model.value.directory, '/other');
      await tester.tap(worktree);
      await tester.pumpAndSettle();
      final staleSelect = tester
          .widget<InlineSelectionPanel<Object>>(card)
          .onSelected!;
      fixture.model.updateDirectory('/changed');
      await tester.pumpAndSettle();
      staleSelect('/workspace');
      expect(fixture.model.value.directory, '/changed');
      await tester.tap(find.byTooltip('Close Worktree choices'));
      await tester.pumpAndSettle();
      await tester.tap(worktree);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new worktree'));
      await tester.pumpAndSettle();
      expect(find.byType(WorktreePicker), findsOneWidget);
      expect(fixture.worktreeCreates, isEmpty);
      final create = find.widgetWithText(AppButton, 'Create worktree');
      final staleCreate = tester.widget<AppButton>(create).onPressed!;
      fixture.model.updateDirectory('/moved');
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(create).onPressed, isNull);
      staleCreate();
      await tester.pumpAndSettle();
      expect(fixture.worktreeCreates, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      await tester.tap(worktree);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new worktree'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New worktree name'),
        'isolated',
      );
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(fixture.worktreeCreates, ['isolated']);
      expect(fixture.model.value.directory, '/new');
      expect(find.byType(WorktreePicker), findsNothing);
      expect(controller.text, 'Prepared worktree draft');
      expect(fixture.created, isEmpty);
    },
  );
  for (final width in [360.0, 400.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'engine choices fit above keyboard width=$width scale=$scale',
        (tester) async {
          final fixture = _Fixture();
          addTearDown(fixture.dispose);
          final controller = TextEditingController(text: 'Preserve draft');
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: promptTheme(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      key: const ValueKey('available-dock'),
                      width: width,
                      height: 400,
                      child: SessionCreationDock(
                        profile: fixture.profile,
                        viewModel: fixture.model,
                        controller: controller,
                        focusNode: focus,
                        onLaunch: (_) {},
                        onExpandedChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(TextField));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Codex'));
          await tester.tap(find.text('Codex'));
          await tester.pumpAndSettle();
          final available = tester.getRect(find.byType(Scaffold));
          final close = find.byTooltip('Close Coding engine choices');
          expect(
            tester.getRect(close).top,
            greaterThanOrEqualTo(available.top),
          );
          expect(close.hitTestable(), findsOneWidget);
          final list = find.byKey(
            const ValueKey('inline-selection-Coding engine'),
          );
          expect(tester.getSize(list).height, lessThanOrEqualTo(112 * scale));
          expect(focus.hasFocus, isTrue);
          await tester.tap(close);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Select model'));
          await tester.pumpAndSettle();
          final composerBefore = tester.getRect(find.byType(TextField));
          final editableBefore = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          await tester.tap(find.text('Select model'));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(TextField)), composerBefore);
          expect(
            tester.state<EditableTextState>(find.byType(EditableText)),
            same(editableBefore),
          );
          final modelClose = find.byTooltip('Close Model choices');
          expect(
            tester.getRect(modelClose).top,
            greaterThanOrEqualTo(available.top),
          );
          expect(modelClose.hitTestable(), findsOneWidget);
          expect(find.text('MODEL').hitTestable(), findsOneWidget);
          expect(focus.hasFocus, isTrue);
          await tester.tap(modelClose);
          await tester.pumpAndSettle();
          fixture.model.updateOptions(
            const PromptExecutionOptions(
              modelProviderId: 'codex',
              modelId: 'actual',
              reasoningEffort: 'focused-custom',
            ),
          );
          await tester.pumpAndSettle();
          if (scale == 1) {
            expect(
              tester.getCenter(find.text('Available model')).dy,
              tester.getCenter(find.text('Focused thinking')).dy,
            );
          }
          await tester.ensureVisible(find.text('Available model'));
          await tester.tap(find.text('Available model'));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(modelClose).top,
            greaterThanOrEqualTo(available.top),
          );
          expect(modelClose.hitTestable(), findsOneWidget);
          expect(find.text('Focused thinking'), findsOneWidget);
          expect(focus.hasFocus, isTrue);
          await tester.tap(modelClose);
          await tester.pumpAndSettle();
          fixture.model.updateOptions(
            const PromptExecutionOptions(
              modelProviderId: 'codex',
              modelId: 'actual',
            ),
          );
          await tester.pumpAndSettle();
          if (scale == 1) {
            expect(
              tester.getCenter(find.text('Available model')).dy,
              tester.getCenter(find.text('Select effort')).dy,
            );
          }
          expect(controller.text, 'Preserve draft');
          expect(fixture.created, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final compact in [false, true]) {
    testWidgets(
      'inline model and effort keep composer focus and close without mutation compact=$compact',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = TextEditingController(text: 'Preserve this draft');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: promptTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(compact ? 2 : 1),
                  viewInsets: const EdgeInsets.only(bottom: 240),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: compact ? 320 : 393,
                    height: compact ? 160 : 580,
                    child: SessionCreationDock(
                      profile: fixture.profile,
                      viewModel: fixture.model,
                      controller: controller,
                      focusNode: focus,
                      onLaunch: (_) {},
                      onExpandedChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> tapVisible(Finder finder) async {
          await tester.pumpAndSettle();
          if (finder.evaluate().isEmpty) {
            final list = find.byType(ListView).last;
            await tester.ensureVisible(list);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              finder,
              80,
              scrollable: find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            );
          }
          final containingList = find.ancestor(
            of: finder,
            matching: find.byType(ListView),
          );
          if (containingList.evaluate().isNotEmpty) {
            final list = containingList.first;
            await Scrollable.of(
              tester.element(list),
            ).position.ensureVisible(tester.renderObject(list), alignment: 0.5);
            await Scrollable.of(tester.element(finder)).position.ensureVisible(
              tester.renderObject(finder),
              alignment: 0.5,
            );
          } else {
            await tester.ensureVisible(finder);
          }
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tapVisible(find.byType(TextField));
        final editingState = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        await tapVisible(find.text('Select model'));
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Apply'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(focus.hasFocus, isTrue);
        expect(
          identical(
            editingState,
            tester.state<EditableTextState>(find.byType(EditableText)),
          ),
          isTrue,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(fixture.model.value.options.modelId, isNull);
        expect(find.byType(SessionCreationDock), findsOneWidget);
        expect(find.byTooltip('Close Model choices'), findsNothing);
        expect(controller.text, 'Preserve this draft');
        expect(focus.hasFocus, isTrue);
        await tapVisible(find.text('Select model'));
        await tapVisible(find.text('Available model'));
        expect(fixture.model.value.options.modelProviderId, 'codex');
        expect(fixture.model.value.options.modelId, 'actual');
        await tapVisible(
          find.byKey(const ValueKey('creation-reasoning-effort')),
        );
        await tapVisible(find.text('Focused thinking'));
        expect(fixture.model.value.options.reasoningEffort, 'focused-custom');
        await tapVisible(
          find.byKey(const ValueKey('creation-reasoning-effort')),
        );
        await tapVisible(find.byTooltip('Close Reasoning effort choices'));
        expect(fixture.model.value.options.reasoningEffort, 'focused-custom');
        expect(controller.text, 'Preserve this draft');
        expect(focus.hasFocus, isTrue);
        expect(
          identical(
            editingState,
            tester.state<EditableTextState>(find.byType(EditableText)),
          ),
          isTrue,
        );
        expect(fixture.created, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'creation permission choice stays inline and becomes part of launch options',
    (tester) async {
      final fixture = _Fixture(permissions: true);
      addTearDown(fixture.dispose);
      final controller = TextEditingController(text: 'Create safely');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 393,
                height: 700,
                child: SessionCreationDock(
                  profile: fixture.profile,
                  viewModel: fixture.model,
                  controller: controller,
                  focusNode: focus,
                  onLaunch: (_) {},
                  onExpandedChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('creation-permission-picker'));
      expect(picker, findsOneWidget);
      expect(tester.widget<CompactChoiceButton>(picker).label, 'Ask');
      tester.widget<CompactChoiceButton>(picker).onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('PERMISSIONS'), findsOneWidget);
      final permissionPanel = tester.widget<InlineSelectionPanel<String?>>(
        find.byType(InlineSelectionPanel<String?>),
      );
      expect(
        permissionPanel.options.every((option) => option.value != null),
        isTrue,
      );
      expect(
        permissionPanel.selected,
        fixture.model.value.capabilities!.defaultPermissionModeId,
      );
      expect(
        find.text('Read-only without approval escalation'),
        findsOneWidget,
      );
      expect(focus.hasFocus, isTrue);
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(fixture.model.value.options.permissionModeId, 'read');
      expect(tester.widget<CompactChoiceButton>(picker).label, 'Read');
      expect(controller.text, 'Create safely');
      expect(focus.hasFocus, isTrue);
      expect(fixture.created, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creation keeps the safe native permission default visible without choices',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 393,
              child: SessionCreationDock(
                profile: fixture.profile,
                viewModel: fixture.model,
                controller: controller,
                focusNode: focus,
                onLaunch: (_) {},
                onExpandedChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('creation-permission-picker'));
      expect(picker, findsOneWidget);
      final button = tester.widget<CompactChoiceButton>(picker);
      expect(button.label, 'Auto');
      expect(button.onPressed, isNull);
      expect(fixture.model.value.options.permissionModeId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Claude creation exposes only approval and no-tool planning', (
    tester,
  ) async {
    final fixture = _Fixture(permissions: true);
    addTearDown(fixture.dispose);
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 393,
            child: SessionCreationDock(
              profile: fixture.profile,
              viewModel: fixture.model,
              controller: controller,
              focusNode: focus,
              onLaunch: (_) {},
              onExpandedChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await fixture.model.selectBackend(AgentBackend.gatewayClaude);
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('creation-permission-picker'));
    final button = tester.widget<CompactChoiceButton>(picker);
    expect(button.label, 'Auto');
    expect(button.onPressed, isNotNull);
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Plan without executing tools'), findsOneWidget);
    expect(find.text('Workspace'), findsNothing);
    expect(find.text('Read'), findsNothing);
    await tester.ensureVisible(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(fixture.model.value.options.permissionModeId, 'plan');
    expect(tester.widget<CompactChoiceButton>(picker).label, 'Plan');
    expect(fixture.created, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'obsolete inline model and effort callbacks cannot change another scope',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = TextEditingController(text: 'Retained draft');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 393,
              child: SessionCreationDock(
                profile: fixture.profile,
                viewModel: fixture.model,
                controller: controller,
                focusNode: focus,
                onLaunch: (_) {},
                onExpandedChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select model'));
      await tester.pumpAndSettle();
      final staleModel = tester
          .widget<InlineSelectionPanel<({String providerId, String modelId})?>>(
            find.byType(
              InlineSelectionPanel<({String providerId, String modelId})?>,
            ),
          )
          .onSelected!;
      await fixture.model.selectBackend(AgentBackend.gatewayClaude);
      await tester.pumpAndSettle();
      staleModel((providerId: 'codex', modelId: 'actual'));
      expect(fixture.model.value.options.modelId, isNull);
      await tester.tap(find.byTooltip('Close Model choices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Available model'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('creation-reasoning-effort')));
      await tester.pumpAndSettle();
      final staleEffort = tester
          .widget<InlineSelectionPanel<String?>>(
            find.byType(InlineSelectionPanel<String?>),
          )
          .onSelected!;
      fixture.model.updateOptions(
        const PromptExecutionOptions(
          modelProviderId: 'claude',
          modelId: 'other',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InlineSelectionPanel<String?>>(
              find.byType(InlineSelectionPanel<String?>),
            )
            .onSelected,
        isNull,
      );
      staleEffort('focused-custom');
      expect(fixture.model.value.options.reasoningEffort, isNull);
      expect(fixture.model.value.options.modelId, 'other');
      expect(controller.text, 'Retained draft');
      expect(fixture.created, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('home image-only send picks once and launches exact selection', (
    tester,
  ) async {
    final image = PromptAttachment(
      name: 'fixture.png',
      bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
    );
    final fixture = _Fixture(picker: _Picker(image));
    addTearDown(fixture.dispose);
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final launches = <SessionLaunch>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: SessionCreationDock(
            profile: fixture.profile,
            viewModel: fixture.model,
            controller: controller,
            focusNode: focus,
            initialDirectory: '/workspace',
            onLaunch: launches.add,
            onExpandedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Attach files'));
    await tester.tap(find.byTooltip('Attach files'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-attachments')), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('New session from draft'));
    await tester.tap(find.byTooltip('New session from draft'));
    await tester.pumpAndSettle();
    expect(launches, hasLength(1));
    expect(launches.single.draft, isEmpty);
    expect(launches.single.attachments, [image]);
    expect(fixture.created, ['codex']);
    image.release();
  });
  for (final compact in [false, true]) {
    testWidgets(
      'folder choices stay inline and preserve prepared execution compact=$compact',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = TextEditingController(text: 'Keep prepared draft');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: promptTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(compact ? 2 : 1),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: compact ? 320 : 393,
                    height: compact ? 160 : 580,
                    child: SessionCreationDock(
                      profile: fixture.profile,
                      viewModel: fixture.model,
                      controller: controller,
                      focusNode: focus,
                      initialDirectory: '/original',
                      onLaunch: (_) {},
                      onExpandedChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> tapVisible(Finder finder) async {
          await tester.pumpAndSettle();
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        final folder = find.byWidgetPredicate(
          (widget) =>
              widget is CreationConfigurationRow && widget.label == 'Folder',
        );
        await tapVisible(find.byType(TextField));
        const options = PromptExecutionOptions(
          modelProviderId: 'codex',
          modelId: 'actual',
          reasoningEffort: 'focused-custom',
        );
        fixture.model.updateOptions(options);
        await tester.pumpAndSettle();
        await tester.ensureVisible(folder);
        final composerBounds = tester.getRect(find.byType(TextField));
        await tapVisible(folder);
        expect(tester.getRect(find.byType(TextField)), composerBounds);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(focus.hasFocus, isTrue);
        expect(find.text('PROJECT'), findsOneWidget);
        expect(find.text('~'), findsNothing);
        await tapVisible(find.text('/workspace'));
        expect(fixture.model.value.directory, '/workspace');
        expect(focus.hasFocus, isTrue);
        await tapVisible(folder);
        expect(
          tester
              .widget<InlineSelectionPanel<String>>(
                find.byType(InlineSelectionPanel<String>),
              )
              .selected,
          '/workspace',
        );
        await tapVisible(find.text('Enter custom path'));
        final custom = find.widgetWithText(
          TextFormField,
          'Absolute server path',
        );
        await tester.ensureVisible(custom);
        await tester.enterText(custom, '~/not-an-absolute-server-path');
        await tapVisible(find.text('Use folder'));
        expect(fixture.model.value.directory, '/workspace');
        expect(
          find.text('Enter an absolute path on the connected machine.'),
          findsOneWidget,
        );
        await tester.ensureVisible(custom);
        await tester.enterText(custom, '/chosen/project');
        await tapVisible(find.text('Use folder'));
        expect(fixture.model.value.directory, '/chosen/project');
        expect(focus.hasFocus, isTrue);
        await tapVisible(folder);
        await tapVisible(find.text('Enter custom path'));
        await tester.ensureVisible(custom);
        await tester.enterText(custom, '/discarded');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SessionCreationDock), findsOneWidget);
        expect(find.text('Project'), findsNothing);
        await tapVisible(folder);
        await tapVisible(find.byTooltip('Close Project choices'));
        expect(fixture.model.value.directory, '/chosen/project');
        expect(controller.text, 'Keep prepared draft');
        expect(fixture.model.value.options.modelId, options.modelId);
        expect(
          fixture.model.value.options.reasoningEffort,
          options.reasoningEffort,
        );
        expect(fixture.model.value.backend, AgentBackend.gatewayCodex);
        expect(fixture.created, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'advertised effort applies exactly, cancels safely and resets with model',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = TextEditingController(text: 'Keep my draft');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 393,
                child: SessionCreationDock(
                  profile: fixture.profile,
                  viewModel: fixture.model,
                  controller: controller,
                  focusNode: focus,
                  onLaunch: (_) {},
                  onExpandedChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('creation-reasoning-effort')),
        findsNothing,
      );
      await tester.tap(find.text('Select model'));
      await tester.pumpAndSettle();
      expect(find.text('Default'), findsNothing);
      expect(find.text('CLI default'), findsNothing);
      expect(find.text('CLI / server default'), findsNothing);
      await tester.tap(find.text('Available model'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('creation-reasoning-effort')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('creation-reasoning-effort')));
      await tester.pumpAndSettle();
      expect(find.text('Reported by the configured engine'), findsOneWidget);
      await tester.tap(find.text('Focused thinking'));
      await tester.pumpAndSettle();
      expect(fixture.model.value.options.reasoningEffort, 'focused-custom');
      expect(find.text('Focused thinking'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('creation-reasoning-effort')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InlineSelectionPanel<String?>>(
              find.byType(InlineSelectionPanel<String?>),
            )
            .selected,
        'focused-custom',
      );
      await tester.tap(find.byTooltip('Close Reasoning effort choices'));
      await tester.pumpAndSettle();
      expect(fixture.model.value.options.reasoningEffort, 'focused-custom');
      await tester.tap(find.byKey(const ValueKey('creation-reasoning-effort')));
      await tester.pumpAndSettle();
      expect(find.text('Engine default'), findsNothing);
      await tester.tap(find.byTooltip('Close Reasoning effort choices'));
      await tester.pumpAndSettle();
      expect(fixture.model.value.options.reasoningEffort, 'focused-custom');
      await tester.tap(find.byKey(const ValueKey('creation-reasoning-effort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(InlineSelectionPanel<String?>),
          matching: find.text('Focused thinking'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Available model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other model'));
      await tester.pumpAndSettle();
      expect(fixture.model.value.options.modelId, 'other');
      expect(fixture.model.value.options.reasoningEffort, isNull);
      expect(
        find.byKey(const ValueKey('creation-reasoning-effort')),
        findsNothing,
      );
      expect(controller.text, 'Keep my draft');
      expect(fixture.created, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focused draft configures actual engine and sends one scoped launch',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      SessionLaunch? launch;
      bool expanded = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: promptTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 393,
                child: SessionCreationDock(
                  profile: fixture.profile,
                  viewModel: fixture.model,
                  controller: controller,
                  focusNode: focus,
                  onLaunch: (value) => launch = value,
                  onExpandedChanged: (value) => expanded = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'First message');
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(find.text('/workspace'), findsOneWidget);
      expect(fixture.created, isEmpty);
      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude Code'));
      await tester.pumpAndSettle();
      expect(controller.text, 'First message');
      expect(fixture.model.value.profile?.backend, AgentBackend.gatewayClaude);
      expect(find.text('Claude Code'), findsOneWidget);
      await tester.tap(find.text('Select model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Available model'));
      await tester.pumpAndSettle();
      expect(fixture.model.value.options.modelId, 'actual');
      await tester.tap(find.text('Available model'));
      await tester.pumpAndSettle();
      final picker = tester
          .widget<InlineSelectionPanel<({String providerId, String modelId})?>>(
            find.byType(
              InlineSelectionPanel<({String providerId, String modelId})?>,
            ),
          );
      expect(picker.selected, (providerId: 'claude', modelId: 'actual'));
      await tester.tap(find.byTooltip('Close Model choices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select worktree'));
      await tester.pumpAndSettle();
      expect(
        find.text('This server does not support creating worktrees.'),
        findsOneWidget,
      );
      expect(fixture.created, isEmpty);
      expect(controller.text, 'First message');
      await tester.tap(find.byTooltip('Close Worktree choices'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New session from draft'));
      await tester.pumpAndSettle();
      expect(fixture.created, ['claude']);
      expect(launch?.profile.backend, AgentBackend.gatewayClaude);
      expect(launch?.draft, 'First message');
      expect(launch?.submitDraft, isTrue);
      expect(launch?.options.modelId, 'actual');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inline draft fits tall keyboard and retains text on close', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.binding.setSurfaceSize(const Size(851, 393));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 140,
              width: 500,
              child: SessionCreationDock(
                profile: fixture.profile,
                viewModel: fixture.model,
                controller: controller,
                focusNode: focus,
                onLaunch: (_) {},
                onExpandedChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Keep draft');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Close new session options'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.text, 'Keep draft');
    expect(fixture.created, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _Picker implements AttachmentPicker {
  _Picker(this.image);
  final PromptAttachment image;
  @override
  Future<AttachmentPickResult> pick() async => AttachmentsPicked([image]);
}

class _Fixture {
  _Fixture({
    AttachmentPicker? picker,
    bool worktrees = false,
    bool permissions = false,
  }) {
    client = MockClient((request) async {
      final path = request.url.path;
      Object data = [];
      if (path == '/prompt/capabilities') {
        data = {
          'protocolVersion': 1,
          if (worktrees) 'machine': {'worktrees': true},
          'engines': {
            for (final engine in ['codex', 'claude'])
              engine: {
                'available': true,
                'features': [
                  'sessions',
                  'text',
                  'abort',
                  if (picker != null) 'attachments',
                  if (picker != null) 'imageAttachments',
                ],
                if (picker != null)
                  'attachmentConstraints': {
                    'mimeTypes': ['image/png'],
                    'maxCount': 5,
                    'maxBytesPerAttachment': 5242880,
                    'maxTotalBytes': 10485760,
                  },
              },
          },
        };
      } else if (path == '/prompt/worktrees') {
        final records = [
          for (final item in [('main', '/workspace'), ('topic', '/other')])
            {
              'branch': item.$1,
              'directory': item.$2,
              'detached': false,
              'locked': false,
            },
        ];
        if (request.method == 'POST') {
          worktreeCreates.add(jsonDecode(request.body)['name'] as String);
          data = {
            'branch': 'new',
            'directory': '/new',
            'detached': false,
            'locked': false,
          };
        } else {
          worktreeLoads++;
          data = {'canCreate': true, 'worktrees': records};
        }
      } else if (path.endsWith('/global/health')) {
        data = <String, Object>{};
      } else if (path.endsWith('/project')) {
        data = [
          {'id': 'project', 'worktree': '/workspace'},
        ];
      } else if (path.endsWith('/session/status')) {
        data = <String, Object>{};
      } else if (path.endsWith('/session') && request.method == 'POST') {
        final engine = request.url.pathSegments[1];
        created.add(engine);
        data = {
          'id': '$engine-created',
          'projectID': 'project',
          'directory': '/workspace',
          'title': 'New',
          'time': {'created': 1, 'updated': 1},
        };
      } else if (path.endsWith('/provider')) {
        final engine = request.url.pathSegments[1];
        data = {
          'all': [
            {
              'id': engine,
              if (permissions && (engine == 'codex' || engine == 'claude'))
                'executionOptions': {
                  'version': 1,
                  'permissionModes': [
                    {
                      'id': 'ask',
                      'label': engine == 'codex' ? 'Ask' : 'Auto',
                      'description': engine == 'codex'
                          ? 'Confirm commands outside the trusted set'
                          : 'Ask before uncertain tool use',
                    },
                    if (engine == 'codex') ...[
                      {
                        'id': 'auto',
                        'label': 'Auto',
                        'description':
                            'Let Codex decide inside the workspace sandbox',
                      },
                      {
                        'id': 'read',
                        'label': 'Read',
                        'description': 'Read-only without approval escalation',
                      },
                    ] else
                      {
                        'id': 'plan',
                        'label': 'Plan',
                        'description': 'Plan without executing tools',
                      },
                  ],
                  'defaultPermissionModeId': 'ask',
                },
              'models': {
                'default': {'name': 'CLI default'},
                'actual': {
                  'name': 'Available model',
                  'executionOptions': {
                    'version': 1,
                    'reasoningEfforts': [
                      {
                        'id': 'focused-custom',
                        'label': 'Focused thinking',
                        'description': 'Reported by the configured engine',
                      },
                    ],
                    'defaultReasoningEffortId': 'focused-custom',
                  },
                },
                'other': {'name': 'Other model'},
              },
            },
          ],
          'connected': [engine],
        };
      }
      return http.Response(jsonEncode(data), 200);
    });
    final transport = OpenCodeTransport(client);
    final credentials = _Credentials();
    model = SessionCreationViewModel(
      worktrees: worktrees
          ? WorktreeRepository(WorktreeService(transport), credentials)
          : null,
      attachmentPicker: picker,
      connections: ConnectionRepository(
        OpenCodeHealthService(transport),
        credentials,
        InMemoryServerProfileStore(),
      ),
      sessions: SessionsRepository(
        OpenCodeSessionsService(transport),
        credentials,
      ),
      capabilities: CapabilitiesRepository(
        OpenCodeCapabilitiesService(transport),
        credentials,
      ),
    );
  }
  final profile = ServerProfile(
    origin: Uri.parse('http://10.0.0.2:4097'),
    username: 'operator',
    backend: AgentBackend.gatewayCodex,
  );
  final created = <String>[];
  final worktreeCreates = <String>[];
  int worktreeLoads = 0;
  late final http.Client client;
  late final SessionCreationViewModel model;
  void dispose() {
    model.dispose();
    client.close();
  }
}

class _Credentials implements CredentialsStore {
  @override
  Future<String?> readPassword(String profileId) async => 'synthetic-password';
  @override
  Future<void> savePassword(String profileId, String? password) async {}
  @override
  Future<void> clearPassword(String profileId) async {}
}

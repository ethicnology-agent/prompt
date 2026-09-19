import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/sessions/presentation/new_session_dock.dart';

void main() {
  testWidgets(
    'controlled focus requests expansion and picker focus loss does not close it',
    (tester) async {
      final draft = TextEditingController();
      final focus = FocusNode();
      addTearDown(draft.dispose);
      addTearDown(focus.dispose);
      var expanded = false;
      final requests = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => NewSessionDock(
                draftController: draft,
                focusNode: focus,
                expanded: expanded,
                configuration: const Text('Creation configuration'),
                onExpandedChanged: (value) {
                  requests.add(value);
                  setState(() => expanded = value);
                },
                onCreate: () {},
                onTerminal: null,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(find.text('Creation configuration'), findsOneWidget);
      expect(requests, [true]);
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(find.text('Creation configuration'), findsOneWidget);
      expect(requests, [true]);
      expect(find.byTooltip('Close new session options'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(expanded, isFalse);
      expect(find.text('Creation configuration'), findsNothing);
      expect(requests, [true, false]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('draft stays editable when creation is not yet available', (
    tester,
  ) async {
    final draft = TextEditingController();
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewSessionDock(
            draftController: draft,
            onCreate: null,
            onTerminal: null,
            configuration: const Text('Loading creation choices'),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Prepare while loading');
    await tester.pump();
    expect(draft.text, 'Prepare while loading');
    expect(find.text('Loading creation choices'), findsOneWidget);
    expect(
      tester.widget<AppIconButton>(find.byType(AppIconButton).last).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('focus expands inline and Back preserves the draft and route', (
    tester,
  ) async {
    final draft = TextEditingController();
    final focus = FocusNode();
    addTearDown(draft.dispose);
    addTearDown(focus.dispose);
    final expansions = <bool>[];
    String? changed;
    var creates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 320,
              child: NewSessionDock(
                draftController: draft,
                focusNode: focus,
                onCreate: () => creates++,
                onTerminal: null,
                onChanged: (value) => changed = value,
                onExpandedChanged: expansions.add,
                configuration: const CreationConfigurationRow(
                  icon: Icons.memory,
                  label: 'Engine',
                  value: 'Actual selected engine',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Actual selected engine'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Actual selected engine'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    expect(changed, 'Keep my draft');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NewSessionDock), findsOneWidget);
    expect(find.text('Actual selected engine'), findsNothing);
    expect(draft.text, 'Keep my draft');
    expect(focus.hasFocus, isFalse);
    expect(expansions, [true, false]);
    expect(creates, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bounded landscape viewport is not reduced by IME twice', (
    tester,
  ) async {
    final draft = TextEditingController();
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(850, 393),
              viewInsets: EdgeInsets.only(bottom: 300),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Center(
              child: SizedBox(
                width: 320,
                height: 140,
                child: NewSessionDock(
                  draftController: draft,
                  expanded: true,
                  onCreate: () {},
                  onTerminal: null,
                  configuration: const CreationConfigurationRow(
                    icon: Icons.folder,
                    label: 'Directory',
                    value: '/workspace',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DraftComposerPanel)).height, 140);
    expect(
      find.byTooltip('New session from draft').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

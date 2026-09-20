import 'dart:ui' show Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? promptDarkTheme() : promptTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  for (final busy in [false, true]) {
    testWidgets('icon has exactly one accessible label busy=$busy', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _host(
            AppIconButton(
              icon: Icons.settings,
              tooltip: 'Execution settings',
              busy: busy,
              onPressed: () {},
            ),
          ),
        );
        final data = tester
            .getSemantics(find.byType(IconButton))
            .getSemanticsData();
        expect(data.label, 'Execution settings');
      } finally {
        semantics.dispose();
      }
    });
  }
  for (final dark in [false, true]) {
    for (final variant in AppButtonVariant.values) {
      testWidgets('$variant supports touch and semantics in dark=$dark', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          var presses = 0;
          await tester.pumpWidget(
            _host(
              AppButton(
                label: 'Continue',
                icon: Icons.arrow_forward,
                variant: variant,
                onPressed: () => presses++,
              ),
              dark: dark,
            ),
          );
          final node = tester.getSemantics(find.text('Continue'));
          expect(node.flagsCollection.isButton, isTrue);
          expect(node.flagsCollection.isEnabled, Tristate.isTrue);
          final size = tester.getSize(find.byType(AppButton));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
          await tester.tap(find.text('Continue'));
          expect(presses, 1);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('disabled and busy buttons do not activate', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppButton(label: 'Disabled', onPressed: null),
            AppButton(label: 'Saving', busy: true, onPressed: () => presses++),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Disabled'));
    await tester.tap(find.text('Saving'));
    expect(presses, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving'), findsOneWidget);
  });

  testWidgets('button supports keyboard activation', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        AppButton(
          label: 'Continue',
          autofocus: true,
          onPressed: () => presses++,
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 1);
  });

  testWidgets('icon button retains its label and touch target while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var presses = 0;
      await tester.pumpWidget(
        _host(
          AppIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            busy: true,
            onPressed: () => presses++,
          ),
        ),
      );
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(tester.getSize(find.byType(AppIconButton)).height, 48);
      await tester.tap(find.byType(AppIconButton));
      expect(presses, 0);
      expect(find.bySemanticsLabel('Refresh'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('text field forwards editing, focus and submission', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    String? changed;
    String? submitted;
    await tester.pumpWidget(
      _host(
        AppTextField(
          label: 'Message',
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.send,
          onChanged: (value) => changed = value,
          onSubmitted: (value) => submitted = value,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Hello');
    expect(controller.text, 'Hello');
    expect(changed, 'Hello');
    expect(focusNode.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(submitted, 'Hello');
  });

  testWidgets('form field validates and saves through the Form contract', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    String? saved;
    await tester.pumpWidget(
      _host(
        Form(
          key: key,
          child: AppTextFormField(
            label: 'Name',
            validator: (value) => value!.isEmpty ? 'Required' : null,
            onSaved: (value) => saved = value,
          ),
        ),
      ),
    );
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Local');
    expect(key.currentState!.validate(), isTrue);
    key.currentState!.save();
    expect(saved, 'Local');
  });

  testWidgets('masked fields disable suggestions and autocorrection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppTextField(label: 'Password', obscureText: true)),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });
}

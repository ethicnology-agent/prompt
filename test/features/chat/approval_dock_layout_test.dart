import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/presentation/widgets/approval_dock.dart';

void main() {
  for (final dark in [false, true]) {
    for (final multiple in [false, true]) {
      testWidgets(
        'question descriptions stay visible and selectable at narrow large text dark=$dark multiple=$multiple',
        (tester) async {
          final semantics = tester.ensureSemantics();
          List<List<String>>? answers;
          const firstDescription =
              'Keep the existing behavior while correcting the selected issue.';
          const secondDescription =
              'Change the behavior and update every affected caller.';
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? promptDarkTheme() : promptTheme(),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: SizedBox(
                    width: 280,
                    height: 360,
                    child: ApprovalDock(
                      maxHeight: 360,
                      approval: PendingQuestionApproval(
                        sessionId: 's',
                        requestId: 'q',
                        questions: [
                          QuestionPrompt(
                            header: 'Approach',
                            question: 'Which approach should be used?',
                            multiple: multiple,
                            allowsCustomAnswer: false,
                            options: const [
                              QuestionOption(
                                label: 'Preserve existing behavior',
                                description: firstDescription,
                              ),
                              QuestionOption(
                                label: 'Update affected callers',
                                description: secondDescription,
                              ),
                            ],
                          ),
                        ],
                      ),
                      onRespondToPermission: (_, _) async => true,
                      onReplyToQuestion: (_, value) async {
                        answers = value;
                        return true;
                      },
                      onRejectQuestion: (_) async => true,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(firstDescription), findsOneWidget);
          expect(find.text(secondDescription), findsOneWidget);
          final scroll = find.byType(Scrollable);
          Future<void> tapDescription(String description) async {
            await tester.scrollUntilVisible(
              find.text(description),
              100,
              scrollable: scroll,
            );
            await tester.tap(find.text(description));
            await tester.pump();
          }

          await tapDescription(firstDescription);
          final firstRow = find.ancestor(
            of: find.text(firstDescription),
            matching: find.byType(ListTile),
          );
          expect(tester.getSize(firstRow).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(firstRow).width, greaterThan(220));
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(firstDescription))),
            findsOneWidget,
          );
          semantics.dispose();
          await tapDescription(secondDescription);
          await tester.scrollUntilVisible(
            find.text('Submit answers'),
            100,
            scrollable: scroll,
          );
          await tester.tap(find.text('Submit answers'));
          await tester.pump();
          expect(answers, [
            multiple
                ? ['Preserve existing behavior', 'Update affected callers']
                : ['Update affected callers'],
          ]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final scale in [1.0, 2.0]) {
    for (final choice in <String, PermissionResponse>{
      'Deny': PermissionResponse.reject,
      'Allow once': PermissionResponse.once,
      'Always allow': PermissionResponse.always,
    }.entries) {
      testWidgets(
        'permission ${choice.key} stays reachable at short height scale $scale',
        (tester) async {
          PermissionResponse? response;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 160,
                    child: ApprovalDock(
                      directory: '/workspace/project',
                      approval: PendingPermissionApproval(
                        sessionId: 'session',
                        permissionId: 'permission',
                        toolType: 'bash',
                        title: 'Exact command detail\n' * 100,
                        alwaysPatterns: const ['git *'],
                        ruleScope: PermissionRuleScope.directoryInstance,
                      ),
                      onRespondToPermission: (_, value) async {
                        response = value;
                        return true;
                      },
                      onReplyToQuestion: (_, _) async => true,
                      onRejectQuestion: (_) async => true,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(response, isNull);
          expect(
            tester.widget<SelectableText>(find.byType(SelectableText)).data,
            'Exact command detail\n' * 100,
          );
          final details = find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.vertical,
          );
          final detailsScrollbar = find.ancestor(
            of: details,
            matching: find.byType(Scrollbar),
          );
          expect(detailsScrollbar, findsOneWidget);
          expect(
            tester.widget<Scrollbar>(detailsScrollbar).thumbVisibility,
            isTrue,
          );
          expect(
            find.bySemanticsLabel('Permission request details'),
            findsOneWidget,
          );
          await tester.drag(details, const Offset(0, -80));
          await tester.pumpAndSettle();
          final detailState = tester.state<ScrollableState>(
            find
                .descendant(of: details, matching: find.byType(Scrollable))
                .first,
          );
          expect(detailState.position.pixels, greaterThan(0));
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.hint ==
                      'Scroll horizontally for more permission options',
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<Scrollbar>(
                  find.ancestor(
                    of: find.byKey(const ValueKey('approval-decisions-scroll')),
                    matching: find.byType(Scrollbar),
                  ),
                )
                .thumbVisibility,
            isTrue,
          );
          final decisions = find.byKey(
            const ValueKey('approval-decisions-scroll'),
          );
          expect(decisions, findsOneWidget);
          await tester.scrollUntilVisible(
            find.text(choice.key).hitTestable(),
            100,
            scrollable: find.descendant(
              of: decisions,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.tap(find.text(choice.key));
          await tester.pump();
          if (choice.value == PermissionResponse.always) {
            expect(response, isNull);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Confirm always allow'));
            await tester.pumpAndSettle();
          }
          expect(response, choice.value);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('long permission details do not hide the decision controls', (
    tester,
  ) async {
    PermissionResponse? response;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 240,
              child: ApprovalDock(
                approval: PendingPermissionApproval(
                  sessionId: 'session',
                  permissionId: 'permission',
                  toolType: 'bash',
                  title: List.filled(80, 'Exact command detail').join('\n'),
                ),
                allowAlways: false,
                onRespondToPermission: (_, value) async {
                  response = value;
                  return true;
                },
                onReplyToQuestion: (_, _) async => true,
                onRejectQuestion: (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Allow once').hitTestable(), findsOneWidget);
    expect(find.text('Deny').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(response, PermissionResponse.reject);
  });
}

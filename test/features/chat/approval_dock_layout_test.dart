import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/presentation/widgets/approval_dock.dart';

void main() {
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

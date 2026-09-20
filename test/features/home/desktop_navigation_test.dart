import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/chat/chat.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/home/presentation/home_shell.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/sessions/presentation/session_creation_dock.dart';

import '../../../tool/ui_preview.dart';
import '../../../tool/ui_preview/offline_client.dart';
import '../../../tool/ui_preview/offline_platform.dart';

// Navigation widget tests isolate transcript transport; the real transcript is
// exercised separately in the browser with the offline protocol fixture.
class _NavigationConversation extends ConversationViewModel {
  _NavigationConversation(AppDependencies deps)
    : super(
        chatRepository: deps.chatRepository,
        sessionsRepository: SessionsRepository(
          OpenCodeSessionsService(deps.transport),
          deps.credentialsStore,
        ),
        queueRepositoryProvider: () async =>
            throw StateError('No queue operation expected'),
        queueCoordinatorProvider: () async =>
            throw StateError('No execution expected'),
        attachmentPicker: OfflineAttachmentPicker(),
      );

  @override
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    messages.value = const ConversationReady([]);
    executionOptionsLoad.value = ExecutionOptionsLoadState.ready;
  }

  @override
  Future<void> leaveSession(OpenCodeSession session) async {}
}

void main() {
  Future<OfflinePreview> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final preview = OfflinePreview();
    final deps = preview.dependencies;
    final conversation = _NavigationConversation(deps);
    final profile = ServerProfile(
      origin: Uri.parse(OfflinePreviewClient.origin),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await conversation.dispose();
      await preview.dependencies.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: promptTheme(),
        home: HomeShell(
          profile: profile,
          sessionsViewModel: deps.sessionsViewModel,
          conversationViewModel: conversation,
          capabilitiesViewModel: deps.capabilitiesViewModel,
          workspaceViewModel: deps.workspaceViewModel,
          terminalViewModel: deps.terminalViewModel,
          diagnosticsViewModel: deps.diagnosticsViewModel,
          voiceViewModel: deps.voiceViewModel,
          localNotificationService: deps.localNotificationService,
          themeViewModel: deps.themeViewModel,
          sessionCreationViewModel: deps.sessionCreationViewModel,
          onSessionLaunched: (_) =>
              fail('Navigation must not create a session'),
          onDisconnect: () {},
          onReconnect: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return preview;
  }

  testWidgets('desktop creation opens in the main pane without sending', (
    tester,
  ) async {
    final preview = await open(tester);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(HomeShell)).toStringDeep(),
      contains('Search sessions'),
    );
    semantics.dispose();
    await tester.tap(find.byTooltip('New session'));
    await tester.pumpAndSettle();
    expect(find.text('New session'), findsWidgets);
    expect(find.text('Ask OpenCode'), findsOneWidget);
    expect(find.byType(SessionsScreen), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Ask OpenCode');
    final catalog = tester.getRect(find.byType(SessionsScreen));
    expect(tester.getRect(field).left, greaterThan(catalog.right));
    await tester.enterText(field, 'A local desktop draft');
    expect(preview.client.acceptedPrompts, 0);

    await tester.tap(find.bySemanticsLabel('Model: Select model'));
    await tester.pumpAndSettle();
    expect(find.text('Offline fixture (no model)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Offline fixture (no model)'), findsNothing);
    expect(find.text('A local desktop draft'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(800, 768));
    await tester.pumpAndSettle();
    expect(find.text('A local desktop draft'), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpAndSettle();
    expect(find.text('A local desktop draft'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New session'));
    await tester.pumpAndSettle();
    expect(find.text('A local desktop draft'), findsOneWidget);
    expect(preview.client.acceptedPrompts, 0);
    await tester.binding.setSurfaceSize(const Size(800, 768));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SessionCreationDock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings and appearance retain the desktop catalog', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsOneWidget);
    final row = find.widgetWithText(ListTile, 'Appearance');
    expect(tester.getSize(row).width, lessThanOrEqualTo(800));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(
      find.text(
        'Choose your preferred color scheme. This preference stays on this device.',
      ),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Your server'), findsOneWidget);
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

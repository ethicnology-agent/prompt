import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_project.dart';
import 'package:prompt/features/workspace/data/workspace_repository.dart';
import 'package:prompt/features/workspace/domain/workspace_entry.dart';
import 'package:prompt/features/workspace/domain/workspace_failure.dart';
import 'package:prompt/features/workspace/presentation/workspace_screen.dart';
import 'package:prompt/features/workspace/presentation/workspace_file_screen.dart';
import 'package:prompt/features/workspace/presentation/workspace_view_model.dart';

void main() {
  for (final kind in WorkspaceSearchKind.values) {
    testWidgets('$kind result opens exact path and preserves query on Back', (
      tester,
    ) async {
      final repo = _Repository()
        ..fileContent = List.generate(
          100,
          (index) => 'line ${index + 1}',
        ).join('\n');
      const path = '/work/été file.dart';
      repo.results = [
        switch (kind) {
          WorkspaceSearchKind.file => const WorkspaceFileSearchResult(
            path: path,
          ),
          WorkspaceSearchKind.text => const WorkspaceTextSearchResult(
            path: path,
            line: 'Matching text',
            lineNumber: 7,
            absoluteOffset: 0,
            matches: [],
          ),
          WorkspaceSearchKind.symbol => const WorkspaceSymbolSearchResult(
            path: 'file:///work/%C3%A9t%C3%A9%20file.dart',
            name: 'MatchingSymbol',
            kind: 1,
            line: 6,
            character: 0,
          ),
        },
      ];
      await _openWorkspace(tester, repo);
      final label = switch (kind) {
        WorkspaceSearchKind.file => 'Files',
        WorkspaceSearchKind.text => 'Text',
        WorkspaceSearchKind.symbol => 'Symbols',
      };
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Files'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(repo.readPaths, isEmpty);
      final resultLabel = switch (kind) {
        WorkspaceSearchKind.file => path,
        WorkspaceSearchKind.text => 'Matching text',
        WorkspaceSearchKind.symbol => 'MatchingSymbol',
      };
      await tester.tap(find.text(resultLabel));
      await tester.pumpAndSettle();
      expect(repo.readPaths, [path]);
      expect(find.byType(WorkspaceFileScreen), findsOneWidget);
      expect(
        tester
            .widget<WorkspaceFileScreen>(find.byType(WorkspaceFileScreen))
            .targetLine,
        kind == WorkspaceSearchKind.file ? null : 7,
      );
      expect(
        tester.widget<CodeLineViewer>(find.byType(CodeLineViewer)).targetLine,
        kind == WorkspaceSearchKind.file ? null : 7,
      );
      if (kind != WorkspaceSearchKind.file) {
        final target = find.byKey(const ValueKey('code-line-7'));
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.widget<Semantics>(target).properties.selected, isTrue);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'needle',
      );
      expect(find.text(resultLabel), findsOneWidget);
      expect(repo.searchKinds, [kind]);
    });
  }

  testWidgets('changed files open and deleted files remain disabled', (
    tester,
  ) async {
    final repo = _Repository()
      ..status = const [
        WorkspaceStatusEntry(
          path: '/work/changed.dart',
          status: WorkspaceFileStatus.modified,
          added: 1,
          removed: 2,
        ),
        WorkspaceStatusEntry(
          path: '/work/deleted.dart',
          status: WorkspaceFileStatus.deleted,
          added: 0,
          removed: 3,
        ),
      ];
    await _openWorkspace(tester, repo);
    await tester.tap(find.byTooltip('Workspace details'));
    await tester.pumpAndSettle();
    final deleted = find.widgetWithText(ListTile, '/work/deleted.dart');
    expect(tester.widget<ListTile>(deleted).onTap, isNull);
    await tester.tap(find.text('/work/deleted.dart'));
    expect(repo.readPaths, isEmpty);
    await tester.tap(find.text('/work/changed.dart'));
    await tester.pumpAndSettle();
    expect(repo.readPaths, ['/work/changed.dart']);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Deleted · Current file unavailable'), findsOneWidget);
  });

  testWidgets(
    'parent action is disabled at root and returns from child directory',
    (tester) async {
      final repo = _Repository()..includeDirectory = true;
      await _openWorkspace(tester, repo);
      AppIconButton parent() => tester.widget<AppIconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIconButton && widget.tooltip == 'Parent directory',
        ),
      );
      expect(parent().onPressed, isNull);
      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(parent().onPressed, isNotNull);
      expect(find.text('/work/src'), findsOneWidget);
      await tester.tap(find.byTooltip('Parent directory'));
      await tester.pumpAndSettle();
      expect(parent().onPressed, isNull);
      expect(repo.loadedPaths, ['/work', '/work/src', '/work']);
    },
  );

  for (final layout in [
    (const Size(851, 393), 300.0, 1.0),
    (const Size(320, 640), 300.0, 2.0),
  ]) {
    testWidgets(
      'workspace controls remain scrollable at ${layout.$1} IME ${layout.$2} scale ${layout.$3}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.$1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await _openWorkspace(tester, _Repository(), scale: layout.$3);
        await tester.ensureVisible(find.byType(TextField));
        await tester.tap(find.byType(TextField));
        tester.view.viewInsets = FakeViewPadding(bottom: layout.$2);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final browser = tester.widget<CustomScrollView>(
          find.byKey(const ValueKey('workspace-browser')),
        );
        final position = browser.controller!.position;
        expect(position.maxScrollExtent, greaterThan(0));
        await tester.scrollUntilVisible(
          find.widgetWithText(ChoiceChip, 'Files'),
          40,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('workspace-browser')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pump();
        expect(
          find.widgetWithText(ChoiceChip, 'Files').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('requires project selection and displays read-only content', (
    tester,
  ) async {
    final viewModel = WorkspaceViewModel(_Repository());
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          profile: ServerProfile(origin: Uri.parse('http://10.80.0.1:4096')),
          projects: const [OpenCodeProject(id: 'project', directory: '/work')],
          viewModel: viewModel,
        ),
      ),
    );

    expect(
      find.text('Select a server project to browse files.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<OpenCodeProject>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('work').last);
    await tester.pumpAndSettle();
    expect(find.text('readme.md'), findsOneWidget);

    await tester.tap(find.text('readme.md'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceFileScreen), findsOneWidget);
    expect(find.text('read-only text'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workspace details'));
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
  });
}

class _Repository implements WorkspaceRepository {
  String fileContent = 'read-only text';
  List<WorkspaceSearchResult> results = [];
  List<WorkspaceStatusEntry> status = [];
  final readPaths = <String>[];
  final loadedPaths = <String>[];
  final searchKinds = <WorkspaceSearchKind>[];
  bool includeDirectory = false;
  @override
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  ) async {
    loadedPaths.add(path);
    return Ok(
      WorkspaceSnapshot(
        entries: [
          if (includeDirectory && path == '/work')
            const WorkspaceEntry(
              name: 'src',
              path: '/work/src',
              isDirectory: true,
              isIgnored: false,
            ),
          const WorkspaceEntry(
            name: 'readme.md',
            path: '/work/readme.md',
            isDirectory: false,
            isIgnored: false,
          ),
        ],
        status: status,
        vcs: const WorkspaceVcsSummary('main'),
      ),
    );
  }

  @override
  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  ) async {
    readPaths.add(path);
    return Ok(WorkspaceFileContent.text(fileContent));
  }

  @override
  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  ) async {
    searchKinds.add(kind);
    return Ok(results);
  }
}

Future<void> _openWorkspace(
  WidgetTester tester,
  _Repository repo, {
  double scale = 1,
}) async {
  final viewModel = WorkspaceViewModel(repo);
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: WorkspaceScreen(
        profile: ServerProfile(origin: Uri.parse('http://10.80.0.1:4096')),
        projects: const [OpenCodeProject(id: 'project', directory: '/work')],
        viewModel: viewModel,
      ),
    ),
  );
  await tester.tap(find.byType(DropdownButtonFormField<OpenCodeProject>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('work').last);
  await tester.pumpAndSettle();
}

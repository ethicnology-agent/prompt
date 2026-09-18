import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/ui/ui.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/workspace/workspace.dart';

class _Repository implements WorkspaceRepository {
  final calls = <({ServerProfile profile, String directory, String path})>[];
  final pending = <Completer<Result<WorkspaceFileContent, WorkspaceFailure>>>[];

  @override
  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  ) {
    calls.add((profile: profile, directory: directory, path: path));
    final request = Completer<Result<WorkspaceFileContent, WorkspaceFailure>>();
    pending.add(request);
    return request.future;
  }

  @override
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  ) => throw StateError('File route must not list workspace');

  @override
  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  ) => throw StateError('File route must not search');
}

void main() {
  final profile = ServerProfile(origin: Uri.parse('http://10.0.0.10:4096'));

  test(
    'file view model uses exact scope and ignores stale completions',
    () async {
      final repository = _Repository();
      final model = WorkspaceFileViewModel(repository);
      addTearDown(model.dispose);
      expect(model.value, isA<WorkspaceFileIdle>());
      final first = model.load(profile, '/first', 'first.dart');
      final second = model.load(
        profile,
        '/second',
        'https://not-a-request.invalid/file',
      );
      expect(model.value, isA<WorkspaceFileLoading>());
      expect(repository.calls[1], (
        profile: profile,
        directory: '/second',
        path: 'https://not-a-request.invalid/file',
      ));
      repository.pending[1].complete(
        const Ok(WorkspaceFileContent.text('new\r\nnext\n')),
      );
      await second;
      expect((model.value as WorkspaceFileReady).lines, ['new', 'next', '']);
      repository.pending[0].complete(const Err(WorkspaceFailure.unavailable));
      await first;
      expect((model.value as WorkspaceFileReady).lines, ['new', 'next', '']);
      expect(
        () => (model.value as WorkspaceFileReady).lines.add('mutation'),
        throwsUnsupportedError,
      );
    },
  );

  test('dispose ignores pending result and later load does not read', () async {
    final repository = _Repository();
    final model = WorkspaceFileViewModel(repository);
    var notifications = 0;
    model.addListener(() => notifications++);
    final request = model.load(profile, '/fixture', 'file');
    model.dispose();
    repository.pending.single.complete(
      const Ok(WorkspaceFileContent.text('late')),
    );
    await request;
    await model.load(profile, '/fixture', 'another');
    expect(repository.calls, hasLength(1));
    expect(notifications, 1);
  });

  test('file factory isolates route state from workspace navigation', () async {
    final repository = _Repository();
    final workspace = WorkspaceViewModel(repository);
    addTearDown(workspace.dispose);
    final first = workspace.createFileViewModel();
    final second = workspace.createFileViewModel();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(identical(first, second), isFalse);
    final request = first.load(profile, '/fixture', 'file');
    repository.pending.single.complete(
      const Err(WorkspaceFailure.unauthorized),
    );
    await request;
    expect(
      (first.value as WorkspaceFileError).failure,
      WorkspaceFailure.unauthorized,
    );
    expect(second.value, isA<WorkspaceFileIdle>());
    expect(workspace.value, isA<WorkspaceIdle>());
  });

  for (final dark in [false, true]) {
    testWidgets(
      'file route retries then shows lazy read-only content dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _Repository();
        final model = WorkspaceFileViewModel(repository);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? promptDarkTheme() : promptTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkspaceFileScreen(
                        profile: profile,
                        directory: '/fixture',
                        path: 'lib/a-long-file-name.dart',
                        viewModel: model,
                      ),
                    ),
                  ),
                  child: const Text('Open file'),
                ),
              ),
            ),
          ),
        );
        expect(repository.calls, isEmpty);
        await tester.tap(find.text('Open file'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(repository.calls, hasLength(1));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        repository.pending[0].complete(const Err(WorkspaceFailure.unavailable));
        await tester.pumpAndSettle();
        expect(find.text(WorkspaceFailure.unavailable.message), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Retry').hitTestable(),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(repository.calls, hasLength(2));
        expect(repository.calls.last, (
          profile: profile,
          directory: '/fixture',
          path: 'lib/a-long-file-name.dart',
        ));
        repository.pending[1].complete(
          Ok(
            WorkspaceFileContent.text(
              List.generate(1000, (index) => 'literal line $index').join('\n'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CodeLineViewer), findsOneWidget);
        expect(find.text('lib/a-long-file-name.dart'), findsOneWidget);
        expect(find.text('Current server file · read-only'), findsOneWidget);
        expect(find.byKey(const ValueKey('code-line-1000')), findsNothing);
        await tester.pump();
        expect(repository.calls, hasLength(2));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(WorkspaceFileScreen), findsNothing);
        await model.load(profile, '/fixture', 'after-pop');
        expect(repository.calls, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final content in [
    const WorkspaceFileContent.binary(),
    const WorkspaceFileContent.text(''),
  ]) {
    testWidgets(
      'file route reports binary=${!content.isText} without renderer',
      (tester) async {
        final repository = _Repository();
        await tester.pumpWidget(
          MaterialApp(
            home: WorkspaceFileScreen(
              profile: profile,
              directory: '/fixture',
              path: 'file',
              viewModel: WorkspaceFileViewModel(repository),
            ),
          ),
        );
        repository.pending.single.complete(Ok(content));
        await tester.pumpAndSettle();
        expect(
          find.text(
            content.isText
                ? 'This file is empty.'
                : 'Binary file preview is unavailable.',
          ),
          findsOneWidget,
        );
        expect(find.byType(CodeLineViewer), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

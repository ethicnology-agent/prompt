import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/sessions/sessions.dart';
import 'package:prompt/features/workspace/workspace.dart';

class _Repository implements WorkspaceRepository {
  final loads = <Completer<Result<WorkspaceSnapshot, WorkspaceFailure>>>[];
  final files = <Completer<Result<WorkspaceFileContent, WorkspaceFailure>>>[];
  final searches =
      <Completer<Result<List<WorkspaceSearchResult>, WorkspaceFailure>>>[];
  final loadScopes = <(String, String, String)>[];

  @override
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  ) {
    loadScopes.add((profile.id, directory, path));
    final result = Completer<Result<WorkspaceSnapshot, WorkspaceFailure>>();
    loads.add(result);
    return result.future;
  }

  @override
  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  ) {
    final result = Completer<Result<WorkspaceFileContent, WorkspaceFailure>>();
    files.add(result);
    return result.future;
  }

  @override
  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  ) {
    final result =
        Completer<Result<List<WorkspaceSearchResult>, WorkspaceFailure>>();
    searches.add(result);
    return result.future;
  }
}

const _snapshot = WorkspaceSnapshot(
  entries: [],
  status: [],
  vcs: WorkspaceVcsSummary('main'),
);
const _project = OpenCodeProject(id: 'project', directory: '/fixture');
const _otherProject = OpenCodeProject(id: 'other', directory: '/other');
const _file = WorkspaceEntry(
  name: 'file',
  path: '/fixture/file',
  isDirectory: false,
  isIgnored: false,
);
const _directory = WorkspaceEntry(
  name: 'nested',
  path: '/fixture/nested',
  isDirectory: true,
  isIgnored: false,
);

void main() {
  final profile = ServerProfile(origin: Uri.parse('http://10.0.0.1:4096'));
  final otherProfile = ServerProfile(origin: Uri.parse('http://10.0.0.2:4096'));
  late _Repository repository;
  late WorkspaceViewModel model;

  setUp(() {
    repository = _Repository();
    model = WorkspaceViewModel(repository);
  });

  Future<void> ready() async {
    final request = model.selectProject(profile, _project);
    repository.loads.last.complete(const Ok(_snapshot));
    await request;
  }

  test(
    'latest project load wins over an earlier successful response',
    () async {
      addTearDown(model.dispose);
      final old = model.selectProject(profile, _project);
      final current = model.selectProject(otherProfile, _otherProject);
      repository.loads[1].complete(const Ok(_snapshot));
      await current;
      repository.loads[0].complete(const Ok(_snapshot));
      await old;
      expect((model.value as WorkspaceReady).project, same(_otherProject));
    },
  );

  test('clear prevents a pending load from resurrecting workspace', () async {
    addTearDown(model.dispose);
    final request = model.selectProject(profile, _project);
    model.clear();
    repository.loads.single.complete(const Ok(_snapshot));
    await request;
    expect(model.value, isA<WorkspaceIdle>());
    await model.refresh(profile);
    expect(repository.loads, hasLength(1));
  });

  test('retry after failure preserves selected nested directory', () async {
    addTearDown(model.dispose);
    await ready();
    expect(model.canGoUp, isFalse);
    final failed = model.openDirectory(profile, _directory);
    repository.loads.last.complete(const Err(WorkspaceFailure.unavailable));
    await failed;
    expect(model.value, isA<WorkspaceError>());
    expect(model.canGoUp, isFalse);
    final retry = model.refresh(profile);
    expect(repository.loads, hasLength(3));
    expect(repository.loadScopes.last, (
      profile.id,
      '/fixture',
      '/fixture/nested',
    ));
    repository.loads.last.complete(const Ok(_snapshot));
    await retry;
    expect((model.value as WorkspaceReady).currentPath, '/fixture/nested');
    expect(model.canGoUp, isTrue);
    final parent = model.goUp(profile);
    repository.loads.last.complete(const Ok(_snapshot));
    await parent;
    expect((model.value as WorkspaceReady).currentPath, '/fixture');
    expect(model.canGoUp, isFalse);
  });

  test('out of order file responses never replace the current file', () async {
    addTearDown(model.dispose);
    await ready();
    final old = model.openFile(profile, _file);
    final current = model.openFile(profile, _file);
    repository.files[1].complete(
      const Ok(WorkspaceFileContent.text('current')),
    );
    await current;
    repository.files[0].complete(const Err(WorkspaceFailure.unauthorized));
    await old;
    final state = model.value as WorkspaceReady;
    expect(state.content?.value, 'current');
    expect(state.contentFailure, isNull);
  });

  test(
    'file response from previous project cannot enter next project',
    () async {
      addTearDown(model.dispose);
      await ready();
      final file = model.openFile(profile, _file);
      final next = model.selectProject(otherProfile, _otherProject);
      repository.loads.last.complete(const Ok(_snapshot));
      await next;
      repository.files.single.complete(
        const Ok(WorkspaceFileContent.text('old scope')),
      );
      await file;
      expect((model.value as WorkspaceReady).content, isNull);
      expect((model.value as WorkspaceReady).project, same(_otherProject));
    },
  );

  test(
    'disposed model ignores load completion and subsequent commands',
    () async {
      final request = model.selectProject(profile, _project);
      model.dispose();
      repository.loads.single.complete(const Ok(_snapshot));
      await expectLater(request, completes);
      await model.selectProject(profile, _project);
      await model.openFile(profile, _file);
      await model.refresh(profile);
      model.clear();
      expect(repository.loads, hasLength(1));
      expect(repository.files, isEmpty);
    },
  );

  test('disposed model ignores a pending file completion', () async {
    await ready();
    final request = model.openFile(profile, _file);
    model.dispose();
    repository.files.single.complete(
      const Ok(WorkspaceFileContent.text('late')),
    );
    await expectLater(request, completes);
  });

  testWidgets(
    'old in-flight search stays isolated after clear and new project',
    (tester) async {
      addTearDown(model.dispose);
      await ready();
      model.search(profile, WorkspaceSearchKind.file, 'old');
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.searches, hasLength(1));
      model.clear();
      final next = model.selectProject(otherProfile, _otherProject);
      repository.loads.last.complete(const Ok(_snapshot));
      await next;
      repository.searches.single.complete(
        const Ok([WorkspaceFileSearchResult(path: 'old')]),
      );
      await tester.pump();
      expect(
        (model.value as WorkspaceReady).search,
        isA<WorkspaceSearchIdle>(),
      );
    },
  );

  testWidgets('dispose cancels debounce and ignores in-flight search', (
    tester,
  ) async {
    await ready();
    model.search(profile, WorkspaceSearchKind.file, 'first');
    await tester.pump(const Duration(milliseconds: 300));
    model.search(profile, WorkspaceSearchKind.file, 'second');
    model.dispose();
    repository.searches.single.complete(
      const Ok([WorkspaceFileSearchResult(path: 'late')]),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.searches, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('commands cannot reuse project scope with a different profile', (
    tester,
  ) async {
    addTearDown(model.dispose);
    await ready();
    final refresh = model.refresh(otherProfile);
    expect(repository.loads, hasLength(1));
    await refresh;
    await model.openDirectory(otherProfile, _directory);
    await model.openFile(otherProfile, _file);
    model.search(otherProfile, WorkspaceSearchKind.file, 'query');
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.loads, hasLength(1));
    expect(repository.files, isEmpty);
    expect(repository.searches, isEmpty);
  });
}

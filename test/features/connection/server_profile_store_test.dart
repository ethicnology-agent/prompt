import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:prompt/data/local/prompt_database.dart' hide ServerProfile;
import 'package:prompt/features/connection/domain/agent_backend.dart';
import 'package:prompt/features/connection/data/server_profile_store.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';

void main() {
  test(
    'encrypted-store mapping restores backend with capabilities unverified',
    () async {
      final database = PromptDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftServerProfileStore(database);
      for (final backend in AgentBackend.values) {
        final profile = ServerProfile(
          origin: Uri.parse('http://10.0.0.1:4096'),
          username: 'prompt',
          backend: backend,
          capabilities: BackendCapabilities([BackendFeature.text]),
        );
        await store.save(profile);
        final restored = await store.load(profile.id);
        expect(restored?.id, profile.id);
        expect(restored?.backend, backend);
        expect(
          restored?.capabilities.supports(BackendFeature.text),
          !backend.isGateway,
        );
      }
    },
  );
  group('InMemoryServerProfileStore', () {
    test('loadLast returns null before anything is saved', () async {
      final store = InMemoryServerProfileStore();

      expect(await store.loadLast(), isNull);
    });

    test('loadLast returns the most recently saved profile', () async {
      final store = InMemoryServerProfileStore();
      await store.save(
        ServerProfile(origin: Uri.parse('http://10.0.0.1:4096')),
      );
      await store.save(
        ServerProfile(
          origin: Uri.parse('http://10.0.0.2:4096'),
          username: 'second',
        ),
      );

      final loaded = await store.loadLast();
      expect(loaded?.displayOrigin, 'http://10.0.0.2:4096');
      expect(loaded?.username, 'second');
    });

    test('never persists past the store instance', () async {
      final store = InMemoryServerProfileStore();
      await store.save(
        ServerProfile(origin: Uri.parse('http://10.0.0.1:4096')),
      );

      final freshStore = InMemoryServerProfileStore();

      expect(await freshStore.loadLast(), isNull);
    });
  });
}

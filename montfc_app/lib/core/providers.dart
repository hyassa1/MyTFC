import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'content/content_store.dart';
import 'database/kv_store.dart';
import 'database/local_database.dart';
import 'security/content_cipher.dart';
import 'security/device_id.dart';
import 'security/key_store.dart';
import 'sync/sync_remote.dart';
import 'sync/sync_service.dart';

/// Fournisseurs Riverpod du socle de l'application.
///
/// [envProvider] et [localDatabaseProvider] sont initialisés dans
/// bootstrap.dart (ProviderScope.overrides) ; les autres en découlent.

final envProvider = Provider<Env>((ref) => throw UnimplementedError('envProvider non initialisé'));

final localDatabaseProvider =
    Provider<LocalDatabase>((ref) => throw UnimplementedError('localDatabaseProvider non initialisé'));

/// Client Supabase, ou null si l'application a été compilée sans serveur.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!ref.watch(envProvider).hasBackend) return null;
  return Supabase.instance.client;
});

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

final kvStoreProvider = Provider<KvStore>((ref) => KvStore(ref.watch(localDatabaseProvider)));

final contentCipherProvider = Provider<ContentCipher>((ref) => ContentCipher(ref.watch(secretStoreProvider)));

final deviceIdProvider = Provider<DeviceIdProvider>((ref) => DeviceIdProvider(ref.watch(secretStoreProvider)));

final syncRemoteProvider = Provider<SyncRemote?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseSyncRemote(client);
});

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(
      local: ref.watch(localDatabaseProvider),
      kv: ref.watch(kvStoreProvider),
      cipher: ref.watch(contentCipherProvider),
      remote: ref.watch(syncRemoteProvider),
    ));

final contentStoreProvider = Provider<ContentStore>((ref) => ContentStore(
      local: ref.watch(localDatabaseProvider),
      kv: ref.watch(kvStoreProvider),
      cipher: ref.watch(contentCipherProvider),
    ));

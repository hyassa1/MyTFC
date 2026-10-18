import 'package:supabase_flutter/supabase_flutter.dart';

/// Accès serveur utilisé par la synchronisation.
///
/// Abstrait pour pouvoir tester le SyncService sans réseau.
abstract interface class SyncRemote {
  /// Appelle la fonction SQL `sync_changes(p_since)`.
  Future<Map<String, dynamic>> syncChanges(DateTime? since);

  /// Appelle la fonction SQL `push_changes(p_works, p_entries)`.
  Future<Map<String, dynamic>> pushChanges(
    List<Map<String, dynamic>> works,
    List<Map<String, dynamic>> entries,
  );
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> syncChanges(DateTime? since) async {
    final res = await _client.rpc<dynamic>(
      'sync_changes',
      params: {'p_since': since?.toUtc().toIso8601String()},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<Map<String, dynamic>> pushChanges(
    List<Map<String, dynamic>> works,
    List<Map<String, dynamic>> entries,
  ) async {
    final res = await _client.rpc<dynamic>(
      'push_changes',
      params: {'p_works': works, 'p_entries': entries},
    );
    return Map<String, dynamic>.from(res as Map);
  }
}

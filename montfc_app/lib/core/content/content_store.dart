import 'dart:convert';

import '../../features/store/domain/entitlement.dart';
import '../database/kv_store.dart';
import '../database/local_database.dart';
import '../security/content_cipher.dart';
import 'content_kinds.dart';

/// Lecture du contenu en cache local (fonctionne entièrement hors ligne).
///
/// Les écritures sont faites uniquement par le SyncService.
class ContentStore {
  ContentStore({
    required this._local,
    required this._kv,
    required this._cipher,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDatabase _local;
  final KvStore _kv;
  final ContentCipher _cipher;
  final DateTime Function() _clock;

  /// Éléments visibles d'un type de contenu (publiés, non supprimés), triés.
  Future<List<Map<String, dynamic>>> list(ContentKind kind) async {
    final rows = await _local.db.query(
      'content_items',
      where: 'kind = ? AND deleted = 0',
      whereArgs: [kind.name],
      orderBy: 'position, id',
    );
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .where((m) => m['is_published'] != false && m['is_active'] != false)
        .toList();
  }

  Future<Map<String, dynamic>?> get(ContentKind kind, String id) async {
    final rows = await _local.db.query(
      'content_items',
      where: 'kind = ? AND id = ? AND deleted = 0',
      whereArgs: [kind.name, id],
      limit: 1,
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
  }

  /// Valeur d'un paramètre `app_settings`.
  Future<Object?> setting(String key) async =>
      (await get(ContentKind.setting, key))?['value'];

  /// Droits d'accès en cache (déchiffrés).
  Future<EntitlementSet> entitlements() async {
    final cipher = await _kv.get(KvStore.entitlementsKey);
    if (cipher == null) return EntitlementSet.empty;
    try {
      final list = (await _cipher.decryptJson(cipher)) as List;
      return EntitlementSet(
        list.map((e) => Entitlement.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
    } on ContentCipherException {
      // Cache altéré : on considère qu'il n'y a aucun droit jusqu'à la
      // prochaine synchronisation.
      return EntitlementSet.empty;
    }
  }

  /// Corps d'un modèle payant, ou null si l'utilisateur n'y a pas (ou plus)
  /// accès, ou s'il n'a pas encore été téléchargé.
  Future<Map<String, dynamic>?> body(BodyKind kind, String templateId) async {
    final rights = await entitlements();
    if (!rights.hasAccess(kind.feature, resourceId: templateId, now: _clock())) return null;

    final rows = await _local.db.query(
      'content_bodies',
      where: 'kind = ? AND template_id = ?',
      whereArgs: [kind.name, templateId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(
        (await _cipher.decryptJson(rows.first['cipher'] as String)) as Map,
      );
    } on ContentCipherException {
      return null;
    }
  }
}

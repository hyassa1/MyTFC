import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/kv_store.dart';
import '../domain/profile.dart';

/// Lecture et enregistrement du profil.
///
/// Le profil est mis en cache localement (clé `user.profile`, aussi remplie
/// par la synchronisation) pour être disponible hors ligne.
abstract interface class ProfileRepository {
  Future<Profile?> cached();

  /// Récupère le profil sur le serveur ; renvoie le cache en cas d'échec réseau.
  Future<Profile?> refresh(String userId);

  /// Enregistre le profil sur le serveur (connexion requise).
  Future<Profile> save(Profile profile);
}

class ProfileSaveException implements Exception {
  const ProfileSaveException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client, this._kv);

  static const cacheKey = 'user.profile';

  final SupabaseClient? _client;
  final KvStore _kv;

  @override
  Future<Profile?> cached() async {
    final raw = await _kv.get(cacheKey);
    if (raw == null) return null;
    return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<Profile?> refresh(String userId) async {
    final client = _client;
    if (client == null) return cached();
    try {
      final row = await client.from('profiles').select().eq('id', userId).maybeSingle();
      if (row == null) return null;
      await _kv.set(cacheKey, jsonEncode(row));
      return Profile.fromJson(row);
    } on SocketException {
      return cached();
    } on PostgrestException {
      return cached();
    }
  }

  @override
  Future<Profile> save(Profile profile) async {
    final client = _client;
    if (client == null) throw const ProfileSaveException('Enregistrement impossible dans cette version.');
    try {
      final row = await client
          .from('profiles')
          .update(profile.toUpdateJson())
          .eq('id', profile.id)
          .select()
          .single();
      await _kv.set(cacheKey, jsonEncode(row));
      return Profile.fromJson(row);
    } on SocketException {
      throw const ProfileSaveException('Pas de connexion internet. Réessaie quand tu seras connecté.');
    } on PostgrestException {
      throw const ProfileSaveException('Enregistrement impossible. Vérifie les informations et réessaie.');
    }
  }
}

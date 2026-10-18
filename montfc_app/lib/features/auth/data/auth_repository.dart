import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';
import '../domain/phone_number.dart';

/// Utilisateur connecté (identité Supabase Auth).
class AuthUser {
  const AuthUser({required this.id, this.phone});

  final String id;
  final String? phone;
}

/// Informations envoyées à la fonction serveur claim-device.
class DeviceInfo {
  const DeviceInfo({
    required this.deviceId,
    required this.platform,
    required this.flavor,
    this.model,
    this.appVersion,
  });

  final String deviceId;
  final String platform;
  final String flavor;
  final String? model;
  final String? appVersion;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'platform': platform,
        'app_flavor': flavor,
        'model': model,
        'app_version': appVersion,
      };
}

/// Authentification par téléphone + code SMS, et règle de l'appareil unique.
abstract interface class AuthRepository {
  AuthUser? get currentUser;

  /// Émet à chaque connexion / déconnexion (y compris une session fermée
  /// par le serveur parce que le compte a été ouvert ailleurs).
  Stream<AuthUser?> get changes;

  Future<void> sendCode(PhoneNumber phone);

  Future<AuthUser> verifyCode(PhoneNumber phone, String code);

  /// Déclare cet appareil comme le seul actif du compte.
  Future<void> claimDevice(DeviceInfo device);

  /// Faux si le compte a été ouvert sur un autre appareil depuis.
  Future<bool> isActiveDevice(String deviceId);

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  AuthUser? get currentUser => _map(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get changes => _client.auth.onAuthStateChange.map((s) => _map(s.session?.user));

  @override
  Future<void> sendCode(PhoneNumber phone) =>
      _guard(() => _client.auth.signInWithOtp(phone: phone.e164, shouldCreateUser: true));

  @override
  Future<AuthUser> verifyCode(PhoneNumber phone, String code) => _guard(() async {
        final res = await _client.auth.verifyOTP(phone: phone.e164, token: code, type: OtpType.sms);
        final user = _map(res.user);
        if (user == null) throw AuthFailure.invalidCode;
        return user;
      });

  @override
  Future<void> claimDevice(DeviceInfo device) =>
      _guard(() => _client.functions.invoke('claim-device', body: device.toJson()));

  @override
  Future<bool> isActiveDevice(String deviceId) => _guard(() async {
        final res = await _client.rpc<dynamic>('is_active_device', params: {'p_device_id': deviceId});
        return res == true;
      });

  @override
  Future<void> signOut() async {
    try {
      // Portée locale : on ne ferme que la session de ce téléphone.
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Hors ligne : la session locale est quand même effacée par le SDK.
    }
  }

  static AuthUser? _map(User? user) => user == null ? null : AuthUser(id: user.id, phone: user.phone);

  /// Traduit les erreurs techniques en messages compréhensibles.
  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthFailure {
      rethrow;
    } on AuthRetryableFetchException {
      // Erreur réseau côté SDK (avant AuthException, dont elle hérite).
      throw AuthFailure.network;
    } on AuthException catch (e) {
      final code = e.code ?? '';
      if (code == 'otp_expired' || code == 'invalid_credentials' || e.statusCode == '403') {
        throw AuthFailure.invalidCode;
      }
      if (code.contains('rate_limit') || e.statusCode == '429') throw AuthFailure.tooManyRequests;
      if (code == 'validation_failed') throw AuthFailure.invalidPhone;
      throw AuthFailure.unknown;
    } on SocketException {
      throw AuthFailure.network;
    } on TimeoutException {
      throw AuthFailure.network;
    } on FunctionException {
      throw AuthFailure.unknown;
    }
  }
}

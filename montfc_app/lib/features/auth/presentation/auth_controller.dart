import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/user_data.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile.dart';
import '../data/auth_repository.dart';
import '../domain/auth_failure.dart';
import '../domain/phone_number.dart';

enum AuthStatus {
  /// Démarrage, session pas encore lue.
  unknown,

  /// Pas de compte : fonctions gratuites uniquement.
  guest,

  /// Connecté.
  signedIn,
}

class AuthState {
  const AuthState({required this.status, this.user, this.profile, this.notice});

  final AuthStatus status;
  final AuthUser? user;
  final Profile? profile;

  /// Message à afficher une fois (ex. session fermée par un autre appareil).
  final String? notice;

  bool get isSignedIn => status == AuthStatus.signedIn;

  /// Connecté mais profil incomplet : on redirige vers la création du profil.
  bool get needsProfile => isSignedIn && !(profile?.isComplete ?? false);

  AuthState copyWith({AuthStatus? status, AuthUser? user, Profile? profile, String? notice}) => AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        profile: profile ?? this.profile,
        notice: notice,
      );
}

// -----------------------------------------------------------------------------
// Fournisseurs
// -----------------------------------------------------------------------------

/// null si l'application a été compilée sans serveur (mode hors ligne seul).
final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAuthRepository(client);
});

final profileRepositoryProvider = Provider<ProfileRepository>(
    (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider), ref.watch(kvStoreProvider)));

final userDataProvider =
    Provider<UserData>((ref) => UserData(ref.watch(localDatabaseProvider), ref.watch(kvStoreProvider)));

/// Informations sur l'appareil envoyées à claim-device.
final deviceInfoProvider = FutureProvider<DeviceInfo>((ref) async {
  final id = await ref.watch(deviceIdProvider).get();
  final flavor = ref.watch(envProvider).flavor.code;
  String platform = 'android';
  String? model;
  try {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      model = '${info.manufacturer} ${info.model}';
    } else if (Platform.isIOS) {
      platform = 'ios';
      model = (await DeviceInfoPlugin().iosInfo).utsname.machine;
    }
  } catch (_) {
    // Le modèle est facultatif.
  }
  return DeviceInfo(deviceId: id, platform: platform, flavor: flavor, model: model);
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

// -----------------------------------------------------------------------------
// Contrôleur
// -----------------------------------------------------------------------------

/// Connexion par code SMS, appareil unique, profil.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<AuthUser?>? _sub;

  /// Vrai pendant une déconnexion demandée par l'étudiant, pour la distinguer
  /// d'une session fermée par le serveur.
  bool _signingOut = false;

  AuthRepository? get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);
    if (repo == null) return const AuthState(status: AuthStatus.guest);

    _sub = repo.changes.listen(_onAuthChange);
    ref.onDispose(() => _sub?.cancel());

    final user = repo.currentUser;
    if (user == null) return const AuthState(status: AuthStatus.guest);

    Future.microtask(() => _restore(user));
    return AuthState(status: AuthStatus.signedIn, user: user);
  }

  /// Session existante au démarrage : profil en cache tout de suite, puis
  /// vérification en ligne de l'appareil et du profil.
  Future<void> _restore(AuthUser user) async {
    final profiles = ref.read(profileRepositoryProvider);
    final cached = await profiles.cached();
    if (cached != null) state = state.copyWith(profile: cached);
    await verifyDevice();
    if (!state.isSignedIn) return;
    final fresh = await profiles.refresh(user.id);
    if (fresh != null && state.isSignedIn) state = state.copyWith(profile: fresh);
  }

  void _onAuthChange(AuthUser? user) {
    if (user == null && state.isSignedIn && !_signingOut) {
      // Session fermée par le serveur (compte ouvert sur un autre téléphone,
      // ou session expirée).
      unawaited(_endSession(
        notice: 'Ta session a été fermée. Si tu t\'es connecté sur un autre téléphone, c\'est normal : '
            'un compte ne peut être actif que sur un seul appareil.',
      ));
    }
  }

  /// Étape 1 : envoi du code par SMS. Renvoie le numéro normalisé.
  Future<PhoneNumber> sendCode(String input) async {
    final repo = _repo;
    if (repo == null) throw AuthFailure.noBackend;
    final phone = PhoneNumber.tryParse(input);
    if (phone == null) throw AuthFailure.invalidPhone;
    await repo.sendCode(phone);
    return phone;
  }

  /// Étape 2 : vérification du code, puis l'appareil devient le seul actif.
  Future<void> verifyCode(PhoneNumber phone, String code) async {
    final repo = _repo;
    if (repo == null) throw AuthFailure.noBackend;
    final cleaned = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) throw AuthFailure.invalidCode;

    final user = await repo.verifyCode(phone, cleaned);
    await repo.claimDevice(await ref.read(deviceInfoProvider.future));
    await ref.read(userDataProvider).attachTo(user.id);

    final profile = await ref.read(profileRepositoryProvider).refresh(user.id);
    state = AuthState(status: AuthStatus.signedIn, user: user, profile: profile);
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
  }

  /// Vérifie que ce téléphone est toujours l'appareil actif du compte.
  /// Appelée au démarrage et à chaque retour au premier plan. Hors ligne,
  /// on ne fait rien (la vérification aura lieu à la reconnexion).
  Future<void> verifyDevice() async {
    final repo = _repo;
    if (repo == null || !state.isSignedIn) return;
    try {
      final deviceId = await ref.read(deviceIdProvider).get();
      if (!await repo.isActiveDevice(deviceId)) {
        await _endSession(
          notice: 'Ton compte a été ouvert sur un autre téléphone. Reconnecte-toi pour l\'utiliser ici.',
        );
      }
    } on AuthFailure {
      // Réseau indisponible : on réessaiera plus tard.
    }
  }

  /// Nombre de modifications non envoyées (pour avertir avant déconnexion).
  Future<int> pendingChanges() => ref.read(userDataProvider).pendingChanges();

  /// Déconnexion demandée par l'étudiant : tout est effacé de ce téléphone.
  Future<void> signOut() async {
    _signingOut = true;
    try {
      await _repo?.signOut();
      await ref.read(userDataProvider).clearAll();
      state = const AuthState(status: AuthStatus.guest);
    } finally {
      _signingOut = false;
    }
  }

  /// Déconnexion imposée : on retire l'accès au contenu payant mais on garde
  /// les travaux non envoyés pour le même compte.
  Future<void> _endSession({required String notice}) async {
    _signingOut = true;
    try {
      await _repo?.signOut();
      await ref.read(userDataProvider).clearAccess();
      state = AuthState(status: AuthStatus.guest, notice: notice);
    } finally {
      _signingOut = false;
    }
  }

  Future<void> saveProfile(Profile profile) async {
    final saved = await ref.read(profileRepositoryProvider).save(profile);
    state = state.copyWith(profile: saved);
  }

  /// Le message a été affiché.
  void clearNotice() => state = state.copyWith();
}

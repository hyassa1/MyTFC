import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/config/env.dart';
import 'package:montfc/core/config/flavor.dart';
import 'package:montfc/core/database/kv_store.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/database/user_data.dart';
import 'package:montfc/core/providers.dart';
import 'package:montfc/core/security/key_store.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/core/sync/sync_service.dart';
import 'package:montfc/features/auth/data/auth_repository.dart';
import 'package:montfc/features/auth/domain/auth_failure.dart';
import 'package:montfc/features/auth/domain/phone_number.dart';
import 'package:montfc/features/auth/presentation/auth_controller.dart';
import 'package:montfc/features/profile/data/profile_repository.dart';
import 'package:montfc/features/profile/domain/profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Serveur d'authentification simulé : un seul appareil actif par compte.
class FakeAuthRepository implements AuthRepository {
  final _changes = StreamController<AuthUser?>.broadcast();
  final List<String> sentCodes = [];
  final List<String> claimedDevices = [];
  String? activeDevice;
  AuthUser? user;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get changes => _changes.stream;

  @override
  Future<void> sendCode(PhoneNumber phone) async => sentCodes.add(phone.e164);

  @override
  Future<AuthUser> verifyCode(PhoneNumber phone, String code) async {
    if (code != '123456') throw AuthFailure.invalidCode;
    user = AuthUser(id: 'user-${phone.nationalNumber}', phone: phone.e164.substring(1));
    _changes.add(user);
    return user!;
  }

  @override
  Future<void> claimDevice(DeviceInfo device) async {
    claimedDevices.add(device.deviceId);
    activeDevice = device.deviceId;
  }

  @override
  Future<bool> isActiveDevice(String deviceId) async => activeDevice == deviceId;

  @override
  Future<void> signOut() async {
    user = null;
    _changes.add(null);
  }

  /// Le serveur ferme la session (ex. connexion sur un autre téléphone).
  void serverClosesSession() {
    user = null;
    _changes.add(null);
  }
}

class FakeProfileRepository implements ProfileRepository {
  Profile? stored;

  @override
  Future<Profile?> cached() async => stored;

  @override
  Future<Profile?> refresh(String userId) async => stored ?? Profile(id: userId);

  @override
  Future<Profile> save(Profile profile) async => stored = profile;
}

class FakeSyncController extends SyncController {
  int calls = 0;

  @override
  SyncState build() => const SyncState();

  @override
  Future<SyncResult> syncNow() async {
    calls++;
    return const SyncResult.skipped();
  }
}

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late ProviderContainer container;

  ProviderContainer build() => ProviderContainer(overrides: [
        envProvider.overrideWithValue(const Env(
          flavor: AppFlavor.direct,
          supabaseUrl: 'https://exemple.supabase.co',
          supabasePublishableKey: 'cle',
        )),
        localDatabaseProvider.overrideWithValue(local),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        syncControllerProvider.overrideWith(FakeSyncController.new),
        deviceInfoProvider.overrideWith((ref) async => DeviceInfo(
              deviceId: await ref.watch(deviceIdProvider).get(),
              platform: 'android',
              flavor: 'direct',
            )),
      ]);

  setUp(() async {
    local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository();
    container = build();
  });

  tearDown(() async {
    container.dispose();
    await local.close();
  });

  AuthController controller() => container.read(authControllerProvider.notifier);
  AuthState state() => container.read(authControllerProvider);
  final phone = PhoneNumber.tryParse('0812345678')!;

  test('sans session : invité', () {
    expect(state().status, AuthStatus.guest);
  });

  test('connexion : code envoyé au numéro normalisé, appareil déclaré actif', () async {
    final normalized = await controller().sendCode('081 234 5678');
    expect(auth.sentCodes, ['+243812345678']);

    await controller().verifyCode(normalized, '123456');
    expect(state().isSignedIn, isTrue);
    expect(state().needsProfile, isTrue, reason: 'nouveau compte : profil à remplir');
    expect(auth.claimedDevices, hasLength(1));
    expect(await KvStore(local).get(UserData.ownerKey), 'user-812345678');
  });

  test('numéro invalide ou code faux : erreur en français, toujours invité', () async {
    expect(() => controller().sendCode('12345'), throwsA(AuthFailure.invalidPhone));
    expect(() => controller().verifyCode(phone, '000000'), throwsA(AuthFailure.invalidCode));
    expect(() => controller().verifyCode(phone, '12'), throwsA(AuthFailure.invalidCode));
    expect(state().status, AuthStatus.guest);
  });

  test('compte ouvert sur un autre téléphone : déconnexion et accès payant retiré', () async {
    await controller().verifyCode(phone, '123456');
    final kv = KvStore(local);
    await kv.set(KvStore.entitlementsKey, 'droits-chiffres');
    await local.db.insert('content_bodies', {'kind': 'cover', 'template_id': 't1', 'cipher': 'x'});
    await local.db.insert('student_works', {
      'id': 'w1',
      'data': jsonEncode({'title': 'Mon sujet'}),
      'updated_at': '2026-10-18T10:00:00Z',
      'dirty': 1,
    });

    auth.activeDevice = 'un-autre-telephone';
    await controller().verifyDevice();

    expect(state().status, AuthStatus.guest);
    expect(state().notice, contains('autre téléphone'));
    expect(await kv.get(KvStore.entitlementsKey), isNull);
    expect(await local.db.query('content_bodies'), isEmpty);
    expect(await local.db.query('student_works'), hasLength(1),
        reason: 'les modifications non envoyées sont gardées pour la reconnexion');
  });

  test('session fermée par le serveur : invité avec un message', () async {
    await controller().verifyCode(phone, '123456');
    auth.serverClosesSession();
    await pumpEventQueue();
    expect(state().status, AuthStatus.guest);
    expect(state().notice, isNotNull);
  });

  test('un autre compte sur le même téléphone : les travaux du précédent sont effacés', () async {
    await controller().verifyCode(phone, '123456');
    await local.db.insert('student_works', {
      'id': 'w1',
      'data': '{}',
      'updated_at': '2026-10-18T10:00:00Z',
      'dirty': 0,
    });
    auth.serverClosesSession();
    await pumpEventQueue();

    await controller().verifyCode(PhoneNumber.tryParse('0992345678')!, '123456');
    expect(await local.db.query('student_works'), isEmpty);
  });

  test('déconnexion volontaire : tout est effacé du téléphone', () async {
    await controller().verifyCode(phone, '123456');
    await local.db.insert('student_works', {'id': 'w1', 'data': '{}', 'updated_at': 'x', 'dirty': 1});
    expect(await controller().pendingChanges(), 1);

    await controller().signOut();
    expect(state().status, AuthStatus.guest);
    expect(state().notice, isNull, reason: 'pas de message pour une déconnexion volontaire');
    expect(await local.db.query('student_works'), isEmpty);
  });

  test('profil enregistré : il n\'est plus demandé', () async {
    await controller().verifyCode(phone, '123456');
    await controller().saveProfile(Profile(
      id: state().user!.id,
      fullName: 'Étudiant Test',
      institutionId: 'i1',
      faculty: 'Droit',
      level: AcademicLevel.g3,
      workType: WorkType.tfc,
      academicYear: '2026-2027',
    ));
    expect(state().needsProfile, isFalse);
  });

  test('appareil toujours actif : rien ne change', () async {
    await controller().verifyCode(phone, '123456');
    await controller().verifyDevice();
    expect(state().isSignedIn, isTrue);
  });
}

import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:montfc/core/config/env.dart';
import 'package:montfc/core/config/flavor.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/providers.dart';
import 'package:montfc/core/security/key_store.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/core/sync/sync_service.dart';
import 'package:montfc/features/auth/data/auth_repository.dart';
import 'package:montfc/features/auth/presentation/auth_controller.dart';
import 'package:montfc/features/store/domain/entitlement.dart';
import 'package:montfc/features/store/domain/offer.dart';

const testUserId = '11111111-1111-4111-8111-111111111111';

const packOffer = Offer(
  id: '00000000-0000-4000-8000-000000000504',
  code: Offer.packCode,
  name: 'Pack Finaliste',
  feature: AppFeature.all,
  isPack: true,
  requiresResource: false,
  durationDays: 365,
  playProductId: 'montfc_pack_finaliste',
  prices: {'CDF': 2900000, 'USD': 1000},
);

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

/// Utilisateur connecté, sans passer par l'écran de connexion.
class SignedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
      status: AuthStatus.signedIn, user: AuthUser(id: testUserId, phone: '243810000001'));
}

List<Override> baseOverrides(LocalDatabase local, {AppFlavor flavor = AppFlavor.direct}) => [
      envProvider.overrideWithValue(Env(
        flavor: flavor,
        supabaseUrl: 'https://exemple.supabase.co',
        supabasePublishableKey: 'cle',
      )),
      localDatabaseProvider.overrideWithValue(local),
      secretStoreProvider.overrideWithValue(MemorySecretStore()),
      syncControllerProvider.overrideWith(FakeSyncController.new),
      authControllerProvider.overrideWith(SignedInAuthController.new),
    ];

/// Attend qu'une condition devienne vraie (minuteries réelles des contrôleurs).
Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition jamais remplie');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

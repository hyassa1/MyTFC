import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../../payment/data/mobile_money_gateway.dart';
import '../data/store_repository.dart';
import '../domain/entitlement.dart';
import '../domain/offer.dart';

final storeRepositoryProvider = Provider<StoreRepository>((ref) => StoreRepository(
      content: ref.watch(contentStoreProvider),
      kv: ref.watch(kvStoreProvider),
      client: ref.watch(supabaseClientProvider),
    ));

/// Offres en vente (cache local, rechargé après chaque synchro).
final offersProvider = FutureProvider<List<Offer>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(storeRepositoryProvider).offers();
});

/// Droits de l'utilisateur (copie locale chiffrée, rechargée après chaque synchro).
final entitlementsProvider = FutureProvider<EntitlementSet>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(contentStoreProvider).entitlements();
});

/// Accès à une fonction (et éventuellement à un modèle précis).
final hasAccessProvider = FutureProvider.family<bool, ({AppFeature feature, String? resourceId})>((ref, q) async {
  final rights = await ref.watch(entitlementsProvider.future);
  return rights.hasAccess(q.feature, resourceId: q.resourceId);
});

final purchaseHistoryProvider = FutureProvider<List<PurchaseRecord>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(storeRepositoryProvider).history();
});

final mobileMoneyGatewayProvider = Provider<MobileMoneyGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseMobileMoneyGateway(client);
});

/// Moyens de paiement proposés dans CETTE variante, sur CETTE plateforme.
///
/// Règle (ARCHITECTURE.md §2) : la variante Play Store ne propose que Google
/// Play Billing, la variante directe le mobile money. Le réglage
/// `payment_channels` de la base permet d'ouvrir d'autres moyens sans
/// republier l'application (si Google ouvre la facturation alternative en RDC).
enum PaymentMethod { mobileMoney, googlePlay, appStore }

final paymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  ref.watch(contentRevisionProvider);
  final flavor = ref.watch(envProvider).flavor.code;
  final platform = Platform.isIOS ? 'ios' : 'android';
  final setting = await ref.watch(contentStoreProvider).setting('payment_channels');
  return paymentMethodsFor(setting, flavor: flavor, platform: platform);
});

/// Lecture du réglage `payment_channels` (fonction pure, testée).
List<PaymentMethod> paymentMethodsFor(Object? setting, {required String flavor, required String platform}) {
  List<String>? fromSetting;
  if (setting is Map && setting[flavor] is Map && (setting[flavor] as Map)[platform] is List) {
    fromSetting = ((setting[flavor] as Map)[platform] as List).whereType<String>().toList();
  }
  // Valeurs par défaut sûres si le réglage est absent.
  final codes = fromSetting ??
      (flavor == 'store' ? [platform == 'ios' ? 'app_store' : 'google_play'] : ['mobile_money']);
  return [
    for (final c in codes)
      if (c == 'mobile_money')
        PaymentMethod.mobileMoney
      else if (c == 'google_play' && platform == 'android')
        PaymentMethod.googlePlay
      else if (c == 'app_store' && platform == 'ios')
        PaymentMethod.appStore,
  ];
}

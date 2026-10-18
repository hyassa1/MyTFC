import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/payment.dart';

/// État d'une transaction Google Play vue par l'application.
enum StoreTransactionStatus { pending, purchased, canceled, error }

/// Transaction remontée par le store (achat neuf ou achat non consommé
/// retrouvé au démarrage).
class StoreTransaction {
  const StoreTransaction({
    required this.playProductId,
    required this.status,
    this.token,
    this.errorMessage,
    this.raw,
  });

  final String playProductId;
  final StoreTransactionStatus status;

  /// Jeton d'achat Google, vérifié par le serveur.
  final String? token;
  final String? errorMessage;

  /// Objet du plugin, nécessaire pour consommer l'achat.
  final Object? raw;
}

/// Facturation du store, derrière une interface pour les tests.
abstract interface class StoreBilling {
  Stream<List<StoreTransaction>> get transactions;
  Future<bool> isAvailable();

  /// Prix affiché par Google dans la devise de l'utilisateur, ou null si le
  /// produit n'est pas (encore) publié dans la Play Console.
  Future<String?> localizedPrice(String playProductId);

  /// Ouvre la feuille de paiement Google. [userId] est lié à l'achat
  /// (obfuscatedAccountId) : le serveur refuse un achat lié à un autre compte.
  /// [resourceId] porte le modèle acheté (obfuscatedProfileId).
  Future<bool> buy({required String playProductId, required String userId, String? resourceId});

  /// Consomme l'achat chez Google, APRÈS validation par le serveur : le même
  /// produit pourra être racheté (renouvellement du pack, autre modèle).
  Future<void> finish(StoreTransaction transaction);

  /// Remonte les achats non consommés (application fermée pendant la vérification).
  Future<void> restore(String userId);
}

class PlayStoreBilling implements StoreBilling {
  PlayStoreBilling([InAppPurchase? iap]) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  final _details = <String, ProductDetails>{};

  @override
  Stream<List<StoreTransaction>> get transactions =>
      _iap.purchaseStream.map((list) => [for (final p in list) _map(p)]);

  StoreTransaction _map(PurchaseDetails p) => StoreTransaction(
        playProductId: p.productID,
        token: p.verificationData.serverVerificationData,
        raw: p,
        errorMessage: p.error?.message,
        status: switch (p.status) {
          PurchaseStatus.pending => StoreTransactionStatus.pending,
          PurchaseStatus.purchased || PurchaseStatus.restored => StoreTransactionStatus.purchased,
          PurchaseStatus.canceled => StoreTransactionStatus.canceled,
          PurchaseStatus.error => StoreTransactionStatus.error,
        },
      );

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetails?> _product(String id) async {
    if (_details[id] case final d?) return d;
    final res = await _iap.queryProductDetails({id});
    for (final d in res.productDetails) {
      _details[d.id] = d;
    }
    return _details[id];
  }

  @override
  Future<String?> localizedPrice(String playProductId) async => (await _product(playProductId))?.price;

  @override
  Future<bool> buy({required String playProductId, required String userId, String? resourceId}) async {
    final details = await _product(playProductId);
    if (details == null) return false;
    return _iap.buyConsumable(
      purchaseParam: Platform.isAndroid
          ? GooglePlayPurchaseParam(
              productDetails: details, applicationUserName: userId, obfuscatedProfileId: resourceId)
          : PurchaseParam(productDetails: details, applicationUserName: userId),
      // Consommation manuelle, seulement après la validation par le serveur.
      autoConsume: false,
    );
  }

  @override
  Future<void> finish(StoreTransaction transaction) async {
    final p = transaction.raw;
    if (p is! PurchaseDetails) return;
    if (Platform.isAndroid) {
      // La consommation vaut aussi accusé de réception chez Google.
      await _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().consumePurchase(p);
    } else if (p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }

  @override
  Future<void> restore(String userId) => _iap.restorePurchases(applicationUserName: userId);
}

/// Résultat de la vérification serveur d'un achat store.
enum StoreVerification { succeeded, pending }

/// Vérification serveur (Edge Function verify-store-purchase).
abstract interface class StorePurchaseVerifier {
  Future<StoreVerification> verify(StoreTransaction transaction);
}

/// Achat refusé par le serveur (jeton invalide, autre compte, achat annulé).
class StorePurchaseRejected implements Exception {
  const StorePurchaseRejected(this.code);
  final String? code;
}

class SupabaseStorePurchaseVerifier implements StorePurchaseVerifier {
  SupabaseStorePurchaseVerifier(this._client);

  final SupabaseClient _client;

  @override
  Future<StoreVerification> verify(StoreTransaction t) async {
    try {
      final res = await _client.functions.invoke('verify-store-purchase', body: {
        'platform': 'android',
        'play_product_id': t.playProductId,
        'purchase_token': t.token,
      }).timeout(const Duration(seconds: 30));
      return res.status == 202 ? StoreVerification.pending : StoreVerification.succeeded;
    } on FunctionException catch (e) {
      // 5xx : problème passager, l'achat sera revérifié plus tard.
      if (e.status >= 500) throw PaymentFailure.network;
      final details = e.details;
      throw StorePurchaseRejected(details is Map ? details['error'] as String? : null);
    } on SocketException {
      throw PaymentFailure.network;
    } on TimeoutException {
      throw PaymentFailure.network;
    }
  }
}

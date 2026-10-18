import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/config/flavor.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/features/payment/data/store_billing.dart';
import 'package:montfc/features/payment/domain/payment.dart';
import 'package:montfc/features/payment/presentation/store_billing_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'payment_test_support.dart';

class FakeBilling implements StoreBilling {
  final controller = StreamController<List<StoreTransaction>>.broadcast();
  final List<String> finished = [];
  final List<({String product, String user, String? resource})> bought = [];
  final List<StoreTransaction> unconsumed = [];

  @override
  Stream<List<StoreTransaction>> get transactions => controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> localizedPrice(String playProductId) async => '10,00 \$US';

  @override
  Future<bool> buy({required String playProductId, required String userId, String? resourceId}) async {
    bought.add((product: playProductId, user: userId, resource: resourceId));
    return true;
  }

  @override
  Future<void> finish(StoreTransaction transaction) async => finished.add(transaction.token!);

  @override
  Future<void> restore(String userId) async => controller.add(List.of(unconsumed));

  void emit(StoreTransactionStatus status, String token) =>
      controller.add([StoreTransaction(playProductId: 'montfc_pack_finaliste', status: status, token: token)]);
}

class FakeVerifier implements StorePurchaseVerifier {
  FakeVerifier(this.answer);

  /// Réponse du serveur par jeton : un résultat, ou une exception à lever.
  final Object Function(String token) answer;
  final List<String> verified = [];

  @override
  Future<StoreVerification> verify(StoreTransaction t) async {
    verified.add(t.token!);
    final a = answer(t.token!);
    if (a is Exception) throw a;
    return a as StoreVerification;
  }
}

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late ProviderContainer container;
  late FakeBilling billing;

  void build(FakeVerifier verifier) {
    container = ProviderContainer(overrides: [
      ...baseOverrides(local, flavor: AppFlavor.store),
      storeBillingProvider.overrideWithValue(billing),
      storePurchaseVerifierProvider.overrideWithValue(verifier),
    ]);
    container.listen(storeBillingControllerProvider, (_, _) {});
  }

  StoreBillingState state() => container.read(storeBillingControllerProvider);

  setUp(() async {
    local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    billing = FakeBilling();
  });

  tearDown(() async {
    container.dispose();
    await local.close();
  });

  test('achat lié au compte, validé par le serveur, PUIS consommé', () async {
    build(FakeVerifier((_) => StoreVerification.succeeded));
    await container.read(storeBillingControllerProvider.notifier).buy(playProductId: 'montfc_pack_finaliste');
    expect(billing.bought.single.user, testUserId);

    billing.emit(StoreTransactionStatus.purchased, 'tok-1');
    await waitFor(() => state().phase == StoreBillingPhase.succeeded);
    expect(billing.finished, ['tok-1']);
    expect((container.read(syncControllerProvider.notifier) as FakeSyncController).calls, 1);
  });

  test('achat refusé par le serveur : jamais consommé (Google rembourse)', () async {
    build(FakeVerifier((_) => const StorePurchaseRejected('invalid_purchase')));
    billing.emit(StoreTransactionStatus.purchased, 'faux');
    await waitFor(() => state().phase == StoreBillingPhase.failed);
    expect(billing.finished, isEmpty);
    expect(state().message, contains('rembours'));
  });

  test('serveur injoignable : achat gardé et revérifié à la reconnexion', () async {
    var online = false;
    build(FakeVerifier((_) => online ? StoreVerification.succeeded : PaymentFailure.network));
    billing.emit(StoreTransactionStatus.purchased, 'tok-2');
    await waitFor(() => state().phase == StoreBillingPhase.pending);
    expect(billing.finished, isEmpty);

    online = true;
    billing.unconsumed.add(const StoreTransaction(
        playProductId: 'montfc_pack_finaliste', status: StoreTransactionStatus.purchased, token: 'tok-2'));
    await container.read(storeBillingControllerProvider.notifier).restore();
    await waitFor(() => state().phase == StoreBillingPhase.succeeded);
    expect(billing.finished, ['tok-2']);
  });

  test('paiement différé chez Google, puis annulation : retour au formulaire', () async {
    build(FakeVerifier((_) => StoreVerification.succeeded));
    billing.emit(StoreTransactionStatus.pending, 'tok-3');
    await waitFor(() => state().phase == StoreBillingPhase.pending);
    billing.emit(StoreTransactionStatus.canceled, 'tok-3');
    await waitFor(() => state().phase == StoreBillingPhase.idle);
    expect(billing.finished, isEmpty);
  });
}

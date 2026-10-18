import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/core/database/kv_store.dart';
import 'package:montfc/core/database/local_database.dart';
import 'package:montfc/core/sync/sync_controller.dart';
import 'package:montfc/features/auth/domain/phone_number.dart';
import 'package:montfc/features/payment/data/mobile_money_gateway.dart';
import 'package:montfc/features/payment/domain/payment.dart';
import 'package:montfc/features/payment/presentation/payment_controller.dart';
import 'package:montfc/features/store/presentation/store_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'payment_test_support.dart';

/// Serveur de paiement simulé : chaque appel à status() renvoie l'état suivant.
class FakeGateway implements MobileMoneyGateway {
  FakeGateway({this.startError, List<PaymentStatus>? statuses, this.failure})
      : statuses = statuses ?? [PaymentStatus.pending];

  final PaymentFailure? startError;
  final List<PaymentStatus> statuses;
  final String? failure;
  final List<MobileMoneyRequest> started = [];
  int statusCalls = 0;
  DateTime expiresAt = DateTime.now().add(const Duration(minutes: 10));

  PaymentAttempt _attempt(PaymentStatus s) => PaymentAttempt(
        id: 'pay-1',
        status: s,
        currency: 'CDF',
        amountNetMinor: 2900000,
        failureReason: s == PaymentStatus.failed ? failure : null,
        expiresAt: expiresAt,
      );

  @override
  Future<PaymentAttempt> start(MobileMoneyRequest request) async {
    if (startError != null) throw startError!;
    started.add(request);
    return _attempt(PaymentStatus.pending);
  }

  @override
  Future<PaymentAttempt> status(String paymentId) async {
    final s = statuses[statusCalls.clamp(0, statuses.length - 1)];
    statusCalls++;
    return _attempt(s);
  }
}

void main() {
  sqfliteFfiInit();

  late LocalDatabase local;
  late ProviderContainer container;

  ProviderContainer build(FakeGateway gateway) => ProviderContainer(overrides: [
        ...baseOverrides(local),
        mobileMoneyGatewayProvider.overrideWithValue(gateway),
        paymentControllerProvider.overrideWith(
            () => PaymentController(pollInterval: const Duration(milliseconds: 10))),
      ]);

  setUp(() async {
    local = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() async {
    container.dispose();
    await local.close();
  });

  final request = MobileMoneyRequest(
    offer: packOffer,
    currency: 'CDF',
    phone: PhoneNumber.tryParse('0810000001')!,
    idempotencyKey: 'cle-1',
  );

  PaymentFlowState listen() {
    // Garde le contrôleur en vie (autoDispose) pendant le test.
    container.listen(paymentControllerProvider, (_, _) {});
    return container.read(paymentControllerProvider);
  }

  test('paiement confirmé sur le téléphone : succès, synchro des droits, attente effacée', () async {
    final gateway = FakeGateway(statuses: [PaymentStatus.processing, PaymentStatus.succeeded]);
    container = build(gateway);
    listen();

    await container.read(paymentControllerProvider.notifier).pay(request);
    expect(container.read(paymentControllerProvider).phase, PaymentPhase.waiting);
    expect(await KvStore(local).get(PaymentController.pendingKey), 'pay-1');

    await waitFor(() => container.read(paymentControllerProvider).phase == PaymentPhase.succeeded);
    expect((container.read(syncControllerProvider.notifier) as FakeSyncController).calls, 1);
    await pumpEventQueue();
    expect(await KvStore(local).get(PaymentController.pendingKey), isNull);
    final calls = gateway.statusCalls;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(gateway.statusCalls, calls, reason: 'le suivi s\'arrête après le résultat');
  });

  test('solde insuffisant : échec avec un message en français', () async {
    container = build(FakeGateway(statuses: [PaymentStatus.failed], failure: 'insufficient_funds'));
    listen();
    await container.read(paymentControllerProvider.notifier).pay(request);
    await waitFor(() => container.read(paymentControllerProvider).phase == PaymentPhase.failed);
    expect(container.read(paymentControllerProvider).error, contains('Solde insuffisant'));
  });

  test('hors ligne au lancement : rien n\'est lancé, message réseau', () async {
    container = build(FakeGateway(startError: PaymentFailure.network));
    listen();
    await container.read(paymentControllerProvider.notifier).pay(request);
    final s = container.read(paymentControllerProvider);
    expect(s.phase, PaymentPhase.failed);
    expect(s.error, PaymentFailure.network.message);
    expect(await KvStore(local).get(PaymentController.pendingKey), isNull);
  });

  test('délai dépassé : on attend encore un peu (succès tardif), puis « délai dépassé »', () async {
    final gateway = FakeGateway(statuses: [PaymentStatus.expired])
      ..expiresAt = DateTime.now().subtract(const Duration(minutes: 5));
    container = build(gateway);
    listen();
    await container.read(paymentControllerProvider.notifier).pay(request);
    await waitFor(() => container.read(paymentControllerProvider).phase == PaymentPhase.expired);
    expect(container.read(paymentControllerProvider).error, contains('pas confirmé'));
  });

  test('succès tardif après expiration (dans le délai de grâce) : débloqué', () async {
    final gateway = FakeGateway(statuses: [PaymentStatus.expired, PaymentStatus.succeeded])
      ..expiresAt = DateTime.now().subtract(const Duration(seconds: 10));
    container = build(gateway);
    listen();
    await container.read(paymentControllerProvider.notifier).pay(request);
    await waitFor(() => container.read(paymentControllerProvider).phase == PaymentPhase.succeeded);
  });

  test('application rouverte pendant l\'attente : le suivi reprend', () async {
    await KvStore(local).set(PaymentController.pendingKey, 'pay-1');
    final gateway = FakeGateway(statuses: [PaymentStatus.pending, PaymentStatus.succeeded]);
    container = build(gateway);
    listen();
    expect(await container.read(paymentControllerProvider.notifier).resumePending(), isTrue);
    expect(container.read(paymentControllerProvider).phase, PaymentPhase.waiting);
    await waitFor(() => container.read(paymentControllerProvider).phase == PaymentPhase.succeeded);
    expect(gateway.started, isEmpty, reason: 'aucun nouveau débit');
  });
}

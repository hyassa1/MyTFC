import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/flavor.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../store/presentation/store_providers.dart';
import '../data/store_billing.dart';
import '../domain/payment.dart';

enum StoreBillingPhase { idle, buying, verifying, pending, succeeded, failed }

class StoreBillingState {
  const StoreBillingState({this.phase = StoreBillingPhase.idle, this.message});

  final StoreBillingPhase phase;
  final String? message;
}

/// Achats Google Play : lance l'achat, puis pour chaque transaction remontée
/// par le store (y compris au démarrage) la fait vérifier par le serveur
/// avant de la consommer. Un achat refusé n'est PAS consommé : Google le
/// rembourse automatiquement s'il n'est pas validé sous 3 jours.
class StoreBillingController extends Notifier<StoreBillingState> {
  StreamSubscription<List<StoreTransaction>>? _sub;

  StoreBilling? get _billing => ref.read(storeBillingProvider);

  @override
  StoreBillingState build() {
    final billing = ref.watch(storeBillingProvider);
    if (billing != null) {
      _sub = billing.transactions.listen(_onTransactions);
      ref.onDispose(() => _sub?.cancel());
    }
    return const StoreBillingState();
  }

  /// Revérifie les achats restés en suspens (appelé après la connexion).
  Future<void> restore() async {
    final userId = ref.read(authControllerProvider).user?.id;
    if (userId == null) return;
    await _billing?.restore(userId);
  }

  Future<void> buy({required String playProductId, String? resourceId}) async {
    final billing = _billing;
    final userId = ref.read(authControllerProvider).user?.id;
    if (billing == null || userId == null) {
      state = const StoreBillingState(phase: StoreBillingPhase.failed, message: 'Achat indisponible.');
      return;
    }
    state = const StoreBillingState(phase: StoreBillingPhase.buying);
    final launched = await billing.buy(playProductId: playProductId, userId: userId, resourceId: resourceId);
    if (!launched) {
      state = const StoreBillingState(
          phase: StoreBillingPhase.failed, message: 'Google Play n\'a pas pu ouvrir le paiement. Réessaie.');
    }
  }

  void reset() => state = const StoreBillingState();

  Future<void> _onTransactions(List<StoreTransaction> list) async {
    for (final t in list) {
      switch (t.status) {
        case StoreTransactionStatus.pending:
          state = const StoreBillingState(
              phase: StoreBillingPhase.pending,
              message: 'Paiement en attente chez Google. Ton accès sera débloqué dès sa confirmation.');
        case StoreTransactionStatus.canceled:
          state = const StoreBillingState();
        case StoreTransactionStatus.error:
          state = StoreBillingState(
              phase: StoreBillingPhase.failed, message: t.errorMessage ?? PaymentFailure.messageFor(null));
        case StoreTransactionStatus.purchased:
          await _verify(t);
      }
    }
  }

  Future<void> _verify(StoreTransaction t) async {
    state = const StoreBillingState(phase: StoreBillingPhase.verifying);
    try {
      final result = await ref.read(storePurchaseVerifierProvider)!.verify(t);
      if (result == StoreVerification.pending) {
        state = const StoreBillingState(
            phase: StoreBillingPhase.pending,
            message: 'Paiement en attente chez Google. Ton accès sera débloqué dès sa confirmation.');
        return;
      }
      await _billing?.finish(t);
      state = const StoreBillingState(phase: StoreBillingPhase.succeeded);
      ref.invalidate(purchaseHistoryProvider);
      unawaited(ref.read(syncControllerProvider.notifier).syncNow());
    } on PaymentFailure {
      // Hors ligne : l'achat reste non consommé et sera revérifié au prochain démarrage.
      state = const StoreBillingState(
          phase: StoreBillingPhase.pending,
          message: 'Achat reçu. Il sera validé dès que tu seras connecté à internet.');
    } on StorePurchaseRejected catch (e) {
      state = StoreBillingState(
        phase: StoreBillingPhase.failed,
        message: e.code == 'purchase_owned_by_other_user'
            ? 'Cet achat appartient à un autre compte MonTFC.'
            : 'Cet achat n\'a pas pu être validé. Si tu as été débité, Google te remboursera automatiquement.',
      );
    }
  }
}

/// Facturation du store : seulement dans la variante store.
final storeBillingProvider = Provider<StoreBilling?>((ref) {
  if (ref.watch(envProvider).flavor != AppFlavor.store) return null;
  return PlayStoreBilling();
});

final storePurchaseVerifierProvider = Provider<StorePurchaseVerifier?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseStorePurchaseVerifier(client);
});

final storeBillingControllerProvider =
    NotifierProvider<StoreBillingController, StoreBillingState>(StoreBillingController.new);

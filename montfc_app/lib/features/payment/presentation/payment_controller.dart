import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../../store/presentation/store_providers.dart';
import '../data/mobile_money_gateway.dart';
import '../domain/payment.dart';

enum PaymentPhase {
  /// Formulaire.
  idle,

  /// Demande envoyée au serveur.
  starting,

  /// L'étudiant doit confirmer sur son téléphone (code PIN).
  waiting,
  succeeded,
  failed,

  /// L'étudiant n'a pas confirmé à temps.
  expired,
}

class PaymentFlowState {
  const PaymentFlowState({this.phase = PaymentPhase.idle, this.attempt, this.error});

  final PaymentPhase phase;
  final PaymentAttempt? attempt;
  final String? error;
}

/// Déroulé d'un paiement mobile money côté application :
/// envoi → attente de la confirmation sur le téléphone (suivi toutes les
/// [pollInterval]) → succès (synchronisation des droits) ou échec.
///
/// L'identifiant du paiement en cours est gardé sur le téléphone : si
/// l'application est fermée pendant l'attente, le suivi reprend à la
/// réouverture de la boutique.
class PaymentController extends Notifier<PaymentFlowState> {
  PaymentController({this.pollInterval = const Duration(seconds: 5), this.grace = const Duration(minutes: 2)});

  static const pendingKey = 'payment.pending_id';

  final Duration pollInterval;

  /// Délai de suivi supplémentaire après l'expiration (succès tardif possible).
  final Duration grace;

  Timer? _timer;
  bool _polling = false;

  MobileMoneyGateway? get _gateway => ref.read(mobileMoneyGatewayProvider);

  @override
  PaymentFlowState build() {
    ref.onDispose(() => _timer?.cancel());
    return const PaymentFlowState();
  }

  Future<void> pay(MobileMoneyRequest request) async {
    final gateway = _gateway;
    if (gateway == null) {
      state = const PaymentFlowState(phase: PaymentPhase.failed, error: 'Paiement indisponible dans cette version.');
      return;
    }
    state = const PaymentFlowState(phase: PaymentPhase.starting);
    try {
      final attempt = await gateway.start(request);
      await ref.read(kvStoreProvider).set(pendingKey, attempt.id);
      _apply(attempt);
    } on PaymentFailure catch (e) {
      state = PaymentFlowState(phase: PaymentPhase.failed, error: e.message);
    }
  }

  /// Reprend le suivi d'un paiement laissé en attente (application fermée).
  Future<bool> resumePending() async {
    final id = await ref.read(kvStoreProvider).get(pendingKey);
    final gateway = _gateway;
    if (id == null || gateway == null) return false;
    try {
      _apply(await gateway.status(id));
      return true;
    } on PaymentFailure {
      // Hors ligne : on garde l'identifiant pour plus tard.
      return false;
    }
  }

  /// Vérifie maintenant (bouton « J'ai confirmé », retour au premier plan).
  Future<void> checkNow() async {
    final id = state.attempt?.id;
    final gateway = _gateway;
    if (id == null || gateway == null || _polling) return;
    _polling = true;
    try {
      _apply(await gateway.status(id));
    } on PaymentFailure {
      // Réseau instable pendant l'attente : on continue d'essayer.
    } finally {
      _polling = false;
    }
  }

  /// Revenir au formulaire (après un échec, pour réessayer).
  void reset() {
    _timer?.cancel();
    state = const PaymentFlowState();
  }

  void _apply(PaymentAttempt attempt) {
    switch (attempt.status) {
      case PaymentStatus.succeeded:
        _finish(PaymentFlowState(phase: PaymentPhase.succeeded, attempt: attempt));
        // Le serveur a créé le droit : on le récupère tout de suite.
        unawaited(ref.read(syncControllerProvider.notifier).syncNow());
      case PaymentStatus.failed || PaymentStatus.cancelled:
        _finish(PaymentFlowState(phase: PaymentPhase.failed, attempt: attempt, error: attempt.failureMessage));
      case PaymentStatus.expired:
        final deadline = (attempt.expiresAt ?? DateTime.now()).add(grace);
        if (DateTime.now().isAfter(deadline)) {
          _finish(PaymentFlowState(phase: PaymentPhase.expired, attempt: attempt,
              error: PaymentFailure.messageFor('timeout')));
        } else {
          state = PaymentFlowState(phase: PaymentPhase.waiting, attempt: attempt);
          _ensurePolling();
        }
      case PaymentStatus.pending || PaymentStatus.processing:
        state = PaymentFlowState(phase: PaymentPhase.waiting, attempt: attempt);
        _ensurePolling();
    }
  }

  void _ensurePolling() {
    if (_timer?.isActive ?? false) return;
    _timer = Timer.periodic(pollInterval, (_) => checkNow());
  }

  void _finish(PaymentFlowState next) {
    _timer?.cancel();
    state = next;
    unawaited(ref.read(kvStoreProvider).remove(pendingKey));
    ref.invalidate(purchaseHistoryProvider);
  }
}

final paymentControllerProvider =
    NotifierProvider.autoDispose<PaymentController, PaymentFlowState>(PaymentController.new);

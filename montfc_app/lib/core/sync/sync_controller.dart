import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'sync_service.dart';

/// État de la synchronisation, affiché discrètement dans l'interface.
class SyncState {
  const SyncState({this.running = false, this.lastResult, this.online = true});

  final bool running;
  final SyncResult? lastResult;
  final bool online;

  SyncState copyWith({bool? running, SyncResult? lastResult, bool? online}) => SyncState(
        running: running ?? this.running,
        lastResult: lastResult ?? this.lastResult,
        online: online ?? this.online,
      );
}

/// Déclenche la synchronisation au démarrage, au retour de la connexion et
/// à la demande (après un achat, par exemple).
class SyncController extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  SyncState build() {
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    ref.onDispose(() => _sub?.cancel());
    // Première synchro après la construction (pas pendant build()).
    Future.microtask(syncNow);
    return const SyncState();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final wasOffline = !state.online;
    state = state.copyWith(online: online);
    if (online && wasOffline) syncNow();
  }

  Future<SyncResult> syncNow() async {
    state = state.copyWith(running: true);
    final result = await ref.read(syncServiceProvider).sync();
    state = state.copyWith(running: false, lastResult: result);
    // Le contenu a pu changer : les écrans qui l'affichent se rechargent.
    if (result.ok && result.pulledAt != null) ref.read(contentRevisionProvider.notifier).bump();
    return result;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Compteur incrémenté à chaque changement du contenu local. Les
/// FutureProvider de contenu le surveillent pour se recharger.
class ContentRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final contentRevisionProvider = NotifierProvider<ContentRevision, int>(ContentRevision.new);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_controller.dart';

/// Petite icône d'état de la synchronisation (barre d'application).
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final (IconData icon, String tip) = switch (sync) {
      SyncState(running: true) => (Icons.sync, 'Synchronisation…'),
      SyncState(online: false) => (Icons.cloud_off_outlined, 'Hors ligne : vos données sont enregistrées sur le téléphone'),
      SyncState(lastResult: final r?) when !r.ok => (Icons.sync_problem_outlined, 'Synchronisation impossible pour le moment'),
      _ => (Icons.cloud_done_outlined, 'À jour'),
    };
    return IconButton(
      tooltip: tip,
      icon: Icon(icon),
      onPressed: sync.running ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
    );
  }
}

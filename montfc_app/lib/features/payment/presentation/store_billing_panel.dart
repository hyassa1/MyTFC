import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../store/domain/offer.dart';
import 'store_billing_controller.dart';

/// Paiement par Google Play (variante store) : prix affiché par Google, achat,
/// puis validation par le serveur.
class StoreBillingPanel extends ConsumerWidget {
  const StoreBillingPanel({super.key, required this.offer, this.resourceId});

  final Offer offer;
  final String? resourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playId = offer.playProductId;
    final billing = ref.watch(storeBillingProvider);
    final state = ref.watch(storeBillingControllerProvider);
    final controller = ref.read(storeBillingControllerProvider.notifier);
    final theme = Theme.of(context);

    if (playId == null || billing == null) {
      return const Center(child: Text('Cette offre n\'est pas disponible sur Google Play.'));
    }

    final busy = state.phase == StoreBillingPhase.buying || state.phase == StoreBillingPhase.verifying;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (offer.description != null) Text(offer.description!),
        const SizedBox(height: 16),
        FutureBuilder<String?>(
          future: billing.localizedPrice(playId),
          builder: (context, snap) => Text(
            snap.connectionState == ConnectionState.waiting
                ? 'Chargement du prix…'
                : snap.data ?? 'Prix indisponible pour le moment.',
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 24),
        switch (state.phase) {
          StoreBillingPhase.succeeded => Column(children: [
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Achat confirmé'),
                subtitle: Text('Ton accès est débloqué. Bon travail !'),
              ),
              FilledButton(
                onPressed: () {
                  controller.reset();
                  context.pop();
                },
                child: const Text('Continuer'),
              ),
            ]),
          StoreBillingPhase.pending => ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: Text(state.message ?? 'Paiement en attente.'),
            ),
          _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.phase == StoreBillingPhase.failed && state.message != null) ...[
                  Text(state.message!, style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: busy ? null : () => controller.buy(playProductId: playId, resourceId: resourceId),
                  child: busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Payer avec Google Play'),
                ),
              ],
            ),
        },
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../payment/presentation/payment_controller.dart';
import '../domain/entitlement.dart';
import '../domain/offer.dart';
import 'store_providers.dart';

/// Offres, droits actifs et historique des achats.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  bool _pendingResumed = false;

  @override
  void initState() {
    super.initState();
    // Un paiement était en attente quand l'application a été fermée ?
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final resumed = await ref.read(paymentControllerProvider.notifier).resumePending();
      if (mounted) setState(() => _pendingResumed = resumed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final offers = ref.watch(offersProvider).value ?? const <Offer>[];
    final rights = ref.watch(entitlementsProvider).value;
    final history = ref.watch(purchaseHistoryProvider);
    final payment = ref.watch(paymentControllerProvider);
    final packEnd = rights?.packExpiry();
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMMd('fr');

    return Scaffold(
      appBar: AppBar(title: const Text('Offres et achats')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(purchaseHistoryProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_pendingResumed && payment.phase == PaymentPhase.waiting)
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.hourglass_top),
                  title: Text('Un paiement est en cours de vérification'),
                  subtitle: Text('Ton accès sera débloqué dès sa confirmation.'),
                ),
              ),
            if (payment.phase == PaymentPhase.succeeded && _pendingResumed)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Ton paiement a été confirmé. Merci !'),
                ),
              ),
            if (packEnd != null)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Pack Finaliste actif'),
                  subtitle: Text('Jusqu\'au ${dateFmt.format(packEnd.toLocal())}'),
                ),
              ),
            const SizedBox(height: 8),
            for (final offer in offers) _OfferCard(offer: offer, owned: _owned(offer, rights)),
            const SizedBox(height: 24),
            Text('Mes achats', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            history.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              error: (_, _) => const Text('Historique indisponible pour le moment.'),
              data: (list) => list.isEmpty
                  ? const Text('Aucun achat pour le moment.')
                  : Column(
                      children: [
                        for (final p in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(offers.where((o) => o.id == p.productId).firstOrNull?.name ?? 'Achat'),
                            subtitle: Text(DateFormat.yMMMd('fr').add_Hm().format(p.createdAt.toLocal())),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(Money.format(p.amountNetMinor, p.currency)),
                                Text(p.statusLabel, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _owned(Offer offer, EntitlementSet? rights) {
    if (rights == null || offer.requiresResource) return false;
    return rights.hasAccess(offer.feature);
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.owned});

  final Offer offer;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prices = [
      if (offer.prices['CDF'] != null) Money.format(offer.prices['CDF']!, 'CDF'),
      if (offer.prices['USD'] != null) Money.format(offer.prices['USD']!, 'USD'),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(offer.name, style: theme.textTheme.titleMedium)),
                if (offer.isPack) const Chip(label: Text('Recommandé'), visualDensity: VisualDensity.compact),
              ],
            ),
            if (offer.description != null) ...[
              const SizedBox(height: 4),
              Text(offer.description!),
            ],
            const SizedBox(height: 8),
            Text(prices, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            if (owned)
              const Row(children: [Icon(Icons.check, size: 18), SizedBox(width: 4), Text('Déjà débloqué')])
            else if (offer.requiresResource)
              OutlinedButton(
                onPressed: () => context.push(offer.code == 'QUESTIONNAIRE' ? Routes.questionnaires : Routes.templates),
                child: const Text('Choisir un modèle'),
              )
            else
              FilledButton(
                onPressed: () => context.push(Routes.purchase, extra: (offer: offer, resourceId: null)),
                child: Text(offer.isPack ? 'Prendre le Pack Finaliste' : 'Acheter'),
              ),
          ],
        ),
      ),
    );
  }
}

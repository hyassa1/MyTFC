import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/security/secure_screen.dart';
import '../../../core/utils/money.dart';
import '../domain/entitlement.dart';
import '../domain/offer.dart';
import 'store_providers.dart';

/// Protège un écran payant : affiche [child] (captures d'écran bloquées)
/// si l'utilisateur a le droit, sinon une invitation à débloquer.
///
/// Le droit testé ici est la copie locale chiffrée, pour le hors-ligne. Le
/// contenu payant lui-même n'est envoyé par le serveur qu'aux ayants droit.
class PaidFeatureGate extends ConsumerWidget {
  const PaidFeatureGate({super.key, required this.feature, this.resourceId, required this.child});

  final AppFeature feature;
  final String? resourceId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(hasAccessProvider((feature: feature, resourceId: resourceId)));
    return access.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Impossible de vérifier ton accès pour le moment.')),
      data: (ok) => ok ? SecureScreen(child: child) : _Upsell(feature: feature, resourceId: resourceId),
    );
  }
}

class _Upsell extends ConsumerWidget {
  const _Upsell({required this.feature, required this.resourceId});

  final AppFeature feature;
  final String? resourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(offersProvider).value ?? const <Offer>[];
    final unit = Offer.forFeature(offers, feature);
    final pack = Offer.pack(offers);
    final theme = Theme.of(context);

    String priceOf(Offer o) => [
          if (o.prices['CDF'] != null) Money.format(o.prices['CDF']!, 'CDF'),
          if (o.prices['USD'] != null) Money.format(o.prices['USD']!, 'USD'),
        ].join(' · ');

    void open(Offer o) => context.push(Routes.purchase, extra: (offer: o, resourceId: o.isPack ? null : resourceId));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Contenu à débloquer', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Les outils gratuits (guide, calcul d\'échantillon, vérification) restent disponibles. '
          'Celui-ci fait partie des outils payants.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Achat à l'unité : seulement si l'offre ne demande pas de choisir un modèle,
        // ou si le modèle est connu.
        if (unit != null && (!unit.requiresResource || resourceId != null)) ...[
          OutlinedButton(onPressed: () => open(unit), child: Text('${unit.name} : ${priceOf(unit)}')),
          const SizedBox(height: 12),
        ],
        if (pack != null)
          FilledButton(onPressed: () => open(pack), child: Text('Pack Finaliste : ${priceOf(pack)}')),
        const SizedBox(height: 12),
        TextButton(onPressed: () => context.push(Routes.store), child: const Text('Voir toutes les offres')),
      ],
    );
  }
}

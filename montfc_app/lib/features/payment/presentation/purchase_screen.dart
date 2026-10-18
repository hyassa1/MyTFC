import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/money.dart';
import '../../auth/domain/phone_number.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../store/domain/offer.dart';
import '../../store/presentation/store_providers.dart';
import '../domain/payment.dart';
import 'payment_controller.dart';
import 'store_billing_panel.dart';

/// Achat d'une offre : choix de la devise, code promo, numéro mobile money,
/// puis attente de la confirmation sur le téléphone.
class PurchaseScreen extends ConsumerWidget {
  const PurchaseScreen({super.key, required this.offer, this.resourceId});

  final Offer offer;
  final String? resourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final flow = ref.watch(paymentControllerProvider);

    final Widget body = switch (flow.phase) {
      PaymentPhase.idle || PaymentPhase.starting => methods.contains(PaymentMethod.mobileMoney)
          ? _MobileMoneyForm(offer: offer, resourceId: resourceId, busy: flow.phase == PaymentPhase.starting)
          : methods.contains(PaymentMethod.googlePlay)
              ? StoreBillingPanel(offer: offer, resourceId: resourceId)
              : const Center(child: Text('Aucun moyen de paiement disponible pour le moment.')),
      PaymentPhase.waiting => _WaitingView(attempt: flow.attempt!),
      PaymentPhase.succeeded => _ResultView(
          icon: Icons.check_circle_outline,
          title: 'Paiement confirmé',
          message: '${offer.name} est débloqué. Bon travail !',
          action: FilledButton(onPressed: () => context.pop(), child: const Text('Continuer')),
        ),
      PaymentPhase.failed || PaymentPhase.expired => _ResultView(
          icon: Icons.error_outline,
          title: flow.phase == PaymentPhase.expired ? 'Délai dépassé' : 'Paiement non abouti',
          message: flow.error ?? PaymentFailure.messageFor(null),
          action: FilledButton(
            onPressed: () => ref.read(paymentControllerProvider.notifier).reset(),
            child: const Text('Réessayer'),
          ),
        ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(offer.name)),
      body: body,
    );
  }
}

class _MobileMoneyForm extends ConsumerStatefulWidget {
  const _MobileMoneyForm({required this.offer, required this.resourceId, required this.busy});

  final Offer offer;
  final String? resourceId;
  final bool busy;

  @override
  ConsumerState<_MobileMoneyForm> createState() => _MobileMoneyFormState();
}

class _MobileMoneyFormState extends ConsumerState<_MobileMoneyForm> {
  late String _currency = widget.offer.prices.containsKey('CDF') ? 'CDF' : 'USD';
  final _phone = TextEditingController();
  final _promo = TextEditingController();
  MobileOperator? _operator;
  Quote? _quote;
  String? _promoError;
  String? _phoneError;

  /// Une clé par achat : un nouvel essai (réseau coupé, double appui) ne
  /// déclenche jamais un second débit.
  final String _idempotencyKey = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    final accountPhone = PhoneNumber.tryParse(ref.read(authControllerProvider).user?.phone ?? '');
    if (accountPhone != null) {
      _phone.text = '0${accountPhone.nationalNumber}';
      _operator = accountPhone.operator;
    }
    _refreshQuote();
  }

  @override
  void dispose() {
    _phone.dispose();
    _promo.dispose();
    super.dispose();
  }

  Future<void> _refreshQuote() async {
    final quote = await ref.read(storeRepositoryProvider).quote(widget.offer, _currency, promoCode: _promo.text);
    if (!mounted) return;
    setState(() {
      _quote = quote;
      _promoError = quote.promoError == null ? null : Quote.promoMessage(quote.promoError!);
    });
  }

  void _pay() {
    final phone = PhoneNumber.tryParse(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = 'Numéro invalide. Exemple : 0812345678.');
      return;
    }
    if (_promoError != null) return;
    ref.read(paymentControllerProvider.notifier).pay(MobileMoneyRequest(
          offer: widget.offer,
          resourceId: widget.resourceId,
          currency: _currency,
          phone: phone,
          operator: _operator ?? phone.operator,
          promoCode: _promo.text.trim().isEmpty ? null : _promo.text.trim(),
          idempotencyKey: _idempotencyKey,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _quote;
    final flowError = ref.watch(paymentControllerProvider).error;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.offer.description != null) Text(widget.offer.description!),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            for (final c in ['CDF', 'USD'])
              if (widget.offer.prices.containsKey(c))
                ButtonSegment(value: c, label: Text(c == 'CDF' ? 'Francs (FC)' : 'Dollars (\$)')),
          ],
          selected: {_currency},
          onSelectionChanged: (s) {
            setState(() => _currency = s.first);
            _refreshQuote();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promo,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: 'Code promo (facultatif)', errorText: _promoError),
                onChanged: (_) => setState(() => _promoError = null),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _refreshQuote, child: const Text('Appliquer')),
          ],
        ),
        const SizedBox(height: 16),
        if (q != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (q.discountMinor > 0) ...[
                    _Line('Prix', Money.format(q.grossMinor, q.currency)),
                    _Line('Réduction', '− ${Money.format(q.discountMinor, q.currency)}'),
                    const Divider(),
                  ],
                  _Line('À payer', Money.format(q.netMinor, q.currency), bold: true),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Numéro mobile money', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+\s]'))],
          decoration: InputDecoration(labelText: 'Numéro', hintText: '0812345678', errorText: _phoneError),
          onChanged: (v) => setState(() {
            _phoneError = null;
            _operator = PhoneNumber.tryParse(v)?.operator ?? _operator;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<MobileOperator>(
          initialValue: _operator,
          decoration: const InputDecoration(labelText: 'Service'),
          items: [
            for (final o in MobileOperator.values) DropdownMenuItem(value: o, child: Text(o.label)),
          ],
          onChanged: (v) => setState(() => _operator = v),
        ),
        if (flowError != null) ...[
          const SizedBox(height: 12),
          Text(flowError, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.busy || q == null ? null : _pay,
          child: widget.busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(q == null ? 'Payer' : 'Payer ${Money.format(q.netMinor, q.currency)}'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tu vas recevoir une demande de confirmation sur ce téléphone. Saisis ton code PIN mobile money pour valider. '
          'Ne communique jamais ce code à personne.',
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }
}

class _WaitingView extends ConsumerStatefulWidget {
  const _WaitingView({required this.attempt});

  final PaymentAttempt attempt;

  @override
  ConsumerState<_WaitingView> createState() => _WaitingViewState();
}

class _WaitingViewState extends ConsumerState<_WaitingView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.attempt.expiresAt?.difference(DateTime.now());
    final remaining = left == null || left.isNegative
        ? null
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Confirme le paiement sur ton téléphone', style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Un message de ton opérateur va s\'afficher : saisis ton code PIN pour payer '
            '${Money.format(widget.attempt.amountNetMinor, widget.attempt.currency)}.',
            textAlign: TextAlign.center,
          ),
          if (remaining != null) ...[
            const SizedBox(height: 8),
            Text('Temps restant : $remaining'),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => ref.read(paymentControllerProvider.notifier).checkNow(),
            child: const Text('J\'ai confirmé'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tu peux fermer cet écran : ton accès sera débloqué dès que le paiement sera confirmé.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.icon, required this.title, required this.message, required this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            action,
          ],
        ),
      );
}

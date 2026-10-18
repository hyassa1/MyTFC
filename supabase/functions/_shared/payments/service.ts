// Déroulé d'un paiement mobile money, indépendant de l'agrégateur.
//
//   1. start()        : l'étudiant choisit l'offre et saisit son numéro ;
//                       on crée le paiement puis on lance la demande (push USSD).
//   2. l'étudiant confirme sur son téléphone (code PIN).
//   3. handleWebhook(): l'agrégateur notifie ; on journalise (idempotence),
//                       on RELIT l'état réel chez l'agrégateur, puis on débloque.
//   4. status()       : l'app interroge régulièrement ; si la notification est
//                       perdue ou en retard, on va chercher l'état nous-mêmes.
//
// Cas gérés : en attente, échec, délai dépassé (cron + rattrapage d'un succès
// tardif), double notification, notification perdue, agrégateur injoignable.

import { HttpError } from '../http.ts';
import type { Currency, MobileOperator, PaymentProvider } from './provider.ts';
import { WebhookRejected } from './provider.ts';
import type { PaymentChannel, PaymentRow, PaymentStore } from './store.ts';

export interface StartPaymentInput {
  product_id: string;
  resource_id?: string | null;
  currency: Currency;
  msisdn: string;
  operator?: MobileOperator | null;
  promo_code?: string | null;
  idempotency_key: string;
  channel?: PaymentChannel;
}

/** Vue d'un paiement renvoyée à l'application (sans données internes). */
export interface PublicPayment {
  id: string;
  status: PaymentRow['status'];
  product_id: string;
  resource_id: string | null;
  currency: Currency;
  amount_gross_minor: number;
  discount_minor: number;
  amount_net_minor: number;
  failure_reason: string | null;
  expires_at: string;
  confirmed_at: string | null;
}

export interface PaymentServiceConfig {
  callbackUrl: string;
  ttlMinutes?: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const OPERATORS: MobileOperator[] = ['vodacom', 'orange', 'airtel', 'afrimoney'];

/** Normalise un numéro mobile congolais en 243XXXXXXXXX, ou lève une erreur 400. */
export function normalizeMsisdn(input: string): string {
  let d = (input ?? '').replace(/[\s\-.()]/g, '');
  if (d.startsWith('+')) d = d.slice(1);
  else if (d.startsWith('00')) d = d.slice(2);
  if (!/^\d+$/.test(d)) throw new HttpError(400, 'invalid_msisdn');
  if (d.length === 12 && d.startsWith('243')) d = d.slice(3);
  else if (d.length === 10 && d.startsWith('0')) d = d.slice(1);
  if (d.length !== 9 || !/^[89]/.test(d)) throw new HttpError(400, 'invalid_msisdn');
  return `243${d}`;
}

export function toPublic(p: PaymentRow): PublicPayment {
  return {
    id: p.id,
    status: p.status,
    product_id: p.product_id,
    resource_id: p.resource_id,
    currency: p.currency,
    amount_gross_minor: Number(p.amount_gross_minor),
    discount_minor: Number(p.discount_minor),
    amount_net_minor: Number(p.amount_net_minor),
    failure_reason: p.failure_reason,
    expires_at: p.expires_at,
    confirmed_at: p.confirmed_at,
  };
}

export class PaymentService {
  constructor(
    private readonly store: PaymentStore,
    private readonly provider: PaymentProvider,
    private readonly config: PaymentServiceConfig,
  ) {}

  async start(userId: string, input: StartPaymentInput): Promise<PublicPayment> {
    if (!input || !UUID.test(input.product_id ?? '')) throw new HttpError(400, 'invalid_product');
    if (input.resource_id && !UUID.test(input.resource_id)) throw new HttpError(400, 'invalid_resource');
    if (input.currency !== 'CDF' && input.currency !== 'USD') throw new HttpError(400, 'invalid_currency');
    if (!input.idempotency_key || input.idempotency_key.length < 8 || input.idempotency_key.length > 100) {
      throw new HttpError(400, 'invalid_idempotency_key');
    }
    if (input.operator && !OPERATORS.includes(input.operator)) throw new HttpError(400, 'invalid_operator');
    const msisdn = normalizeMsisdn(input.msisdn);

    let payment = await this.store.createPayment({
      userId,
      productId: input.product_id,
      resourceId: input.resource_id ?? null,
      currency: input.currency,
      channel: input.channel === 'mobile_money_web' ? 'mobile_money_web' : 'mobile_money_app',
      provider: this.provider.name,
      msisdn,
      operator: input.operator ?? null,
      promoCode: input.promo_code?.trim() || null,
      // Clé préfixée par l'utilisateur : deux comptes ne peuvent pas entrer en collision.
      idempotencyKey: `${userId}:${input.idempotency_key}`,
      ttlMinutes: this.config.ttlMinutes ?? 10,
    });

    // Même clé d'idempotence (double clic, nouvel essai réseau) : la demande
    // a déjà été lancée, on ne relance pas l'agrégateur.
    if (payment.status !== 'pending' || payment.provider_reference) return toPublic(payment);

    const init = await this.provider.initiate({
      paymentId: payment.id,
      msisdn,
      operator: input.operator ?? undefined,
      currency: payment.currency,
      amountMinor: Number(payment.amount_net_minor),
      callbackUrl: this.config.callbackUrl,
      description: 'MonTFC',
    });

    if (!init.ok) {
      await this.store.fail(payment.id, 'failed', init.reason.slice(0, 200));
    } else {
      payment = await this.store.markProcessing(payment.id, init.providerReference);
      return toPublic(payment);
    }
    return toPublic((await this.store.getPayment(payment.id))!);
  }

  /** Renvoie le code HTTP à répondre à l'agrégateur et un petit corps JSON. */
  async handleWebhook(req: Request): Promise<{ status: number; body: Record<string, unknown> }> {
    let event;
    try {
      event = await this.provider.parseWebhook(req);
    } catch (e) {
      if (e instanceof WebhookRejected) return { status: 401, body: { error: e.message } };
      throw e;
    }

    let payment: PaymentRow | null = null;
    if (event.paymentId && UUID.test(event.paymentId)) payment = await this.store.getPayment(event.paymentId);
    if (!payment && event.providerReference) {
      payment = await this.store.findByProviderReference(this.provider.name, event.providerReference);
    }

    const isNew = await this.store.recordEvent(this.provider.name, event.eventId, payment?.id ?? null, event.payload);
    if (!isNew) return { status: 200, body: { ok: true, duplicate: true } };
    // Paiement inconnu : on répond 200 pour que l'agrégateur arrête de
    // renvoyer, l'événement reste journalisé pour enquête.
    if (!payment) return { status: 200, body: { ok: true, unknown_payment: true } };

    const updated = await this.reconcile(payment);
    return { status: 200, body: { ok: true, status: updated.status } };
  }

  /** État d'un paiement pour son propriétaire, avec vérification chez l'agrégateur si besoin. */
  async status(userId: string, paymentId: string): Promise<PublicPayment> {
    if (!UUID.test(paymentId ?? '')) throw new HttpError(400, 'invalid_payment_id');
    const payment = await this.store.getPayment(paymentId);
    if (!payment || payment.user_id !== userId) throw new HttpError(404, 'payment_not_found');
    return toPublic(await this.reconcile(payment));
  }

  /**
   * Relit l'état réel chez l'agrégateur et l'applique (idempotent).
   * Un paiement « expired » est encore vérifié : si l'étudiant a été débité
   * après le délai, il est débloqué.
   */
  async reconcile(payment: PaymentRow): Promise<PaymentRow> {
    if (!['pending', 'processing', 'expired'].includes(payment.status)) return payment;
    if (!payment.provider_reference) return payment;

    const st = await this.provider.checkStatus(payment.provider_reference);
    if (st.status === 'succeeded') {
      await this.store.confirm(payment.id, st.providerReference);
    } else if (st.status === 'failed') {
      await this.store.fail(payment.id, 'failed', st.reason.slice(0, 200));
    } else {
      return payment;
    }
    return (await this.store.getPayment(payment.id)) ?? payment;
  }
}

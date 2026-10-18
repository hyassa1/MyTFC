// Accès à la base pour le paiement. Toute la logique sensible (prix, codes
// promo, idempotence, déblocage) est dans les fonctions SQL ; ce fichier ne
// fait que les appeler.

import type { SupabaseClient } from '@supabase/supabase-js';
import { HttpError } from '../http.ts';
import type { Currency, MobileOperator } from './provider.ts';

export type PaymentStatus = 'pending' | 'processing' | 'succeeded' | 'failed' | 'expired' | 'cancelled';
export type PaymentChannel = 'mobile_money_app' | 'mobile_money_web';

export interface PaymentRow {
  id: string;
  user_id: string;
  product_id: string;
  resource_id: string | null;
  channel: string;
  provider: string;
  currency: Currency;
  amount_gross_minor: number;
  discount_minor: number;
  amount_net_minor: number;
  msisdn: string | null;
  status: PaymentStatus;
  provider_reference: string | null;
  failure_reason: string | null;
  expires_at: string;
  confirmed_at: string | null;
  created_at: string;
}

export interface CreatePaymentArgs {
  userId: string;
  productId: string;
  resourceId: string | null;
  currency: Currency;
  channel: PaymentChannel;
  provider: string;
  msisdn: string;
  operator: MobileOperator | null;
  promoCode: string | null;
  idempotencyKey: string;
  ttlMinutes: number;
}

export interface PaymentStore {
  createPayment(args: CreatePaymentArgs): Promise<PaymentRow>;
  markProcessing(paymentId: string, providerReference: string): Promise<PaymentRow>;
  confirm(paymentId: string, providerReference: string): Promise<void>;
  fail(paymentId: string, status: 'failed' | 'expired' | 'cancelled', reason: string): Promise<void>;
  /** false si l'événement a déjà été reçu (double notification). */
  recordEvent(provider: string, eventId: string, paymentId: string | null, payload: unknown): Promise<boolean>;
  getPayment(paymentId: string): Promise<PaymentRow | null>;
  findByProviderReference(provider: string, providerReference: string): Promise<PaymentRow | null>;
}

/** Codes d'erreur métier levés par les fonctions SQL (raise exception '...'). */
const BUSINESS_ERRORS = new Set([
  'product_not_found',
  'price_not_found',
  'resource_required',
  'resource_not_allowed',
  'resource_not_found',
  'promo_invalid',
  'promo_not_started',
  'promo_expired',
  'promo_exhausted',
  'promo_not_applicable',
  'idempotency_key_conflict',
]);

/** Convertit une erreur SQL métier en erreur HTTP 400 lisible par l'app. */
export function toHttpError(e: unknown): unknown {
  const message = (e as { message?: string })?.message ?? '';
  const code = [...BUSINESS_ERRORS].find((c) => message.includes(c));
  return code ? new HttpError(code === 'idempotency_key_conflict' ? 409 : 400, code) : e;
}

/** Implémentation de production : appels RPC avec la clé service_role. */
export class SupabasePaymentStore implements PaymentStore {
  constructor(private readonly db: SupabaseClient) {}

  async createPayment(a: CreatePaymentArgs): Promise<PaymentRow> {
    const { data, error } = await this.db.rpc('create_payment', {
      p_user_id: a.userId,
      p_product_id: a.productId,
      p_resource_id: a.resourceId,
      p_currency: a.currency,
      p_channel: a.channel,
      p_provider: a.provider,
      p_msisdn: a.msisdn,
      p_operator: a.operator,
      p_promo_code: a.promoCode,
      p_idempotency_key: a.idempotencyKey,
      p_ttl_minutes: a.ttlMinutes,
    });
    if (error) throw toHttpError(error);
    return data as PaymentRow;
  }

  async markProcessing(id: string, ref: string): Promise<PaymentRow> {
    const { data, error } = await this.db.rpc('mark_payment_processing', { p_payment_id: id, p_provider_reference: ref });
    if (error) throw error;
    return data as PaymentRow;
  }

  async confirm(id: string, ref: string): Promise<void> {
    const { error } = await this.db.rpc('confirm_payment', { p_payment_id: id, p_provider_reference: ref });
    if (error) throw error;
  }

  async fail(id: string, status: 'failed' | 'expired' | 'cancelled', reason: string): Promise<void> {
    const { error } = await this.db.rpc('fail_payment', { p_payment_id: id, p_status: status, p_reason: reason });
    if (error) throw error;
  }

  async recordEvent(provider: string, eventId: string, paymentId: string | null, payload: unknown): Promise<boolean> {
    const { data, error } = await this.db.rpc('record_payment_event', {
      p_provider: provider,
      p_provider_event_id: eventId,
      p_payment_id: paymentId,
      p_payload: payload,
    });
    if (error) throw error;
    return data === true;
  }

  async getPayment(id: string): Promise<PaymentRow | null> {
    const { data, error } = await this.db.from('payments').select('*').eq('id', id).maybeSingle();
    if (error) throw error;
    return data as PaymentRow | null;
  }

  async findByProviderReference(provider: string, ref: string): Promise<PaymentRow | null> {
    const { data, error } = await this.db.from('payments').select('*')
      .eq('provider', provider).eq('provider_reference', ref).maybeSingle();
    if (error) throw error;
    return data as PaymentRow | null;
  }
}

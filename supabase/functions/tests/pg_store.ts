// PaymentStore branché directement sur PostgreSQL, pour tester le flux de
// paiement contre les VRAIES fonctions SQL (create_payment, confirm_payment…)
// sans projet Supabase. Utilisé uniquement par les tests.

import postgres from 'postgres';
import type { CreatePaymentArgs, PaymentRow, PaymentStore } from '../_shared/payments/store.ts';
import { toHttpError } from '../_shared/payments/store.ts';

export type Sql = ReturnType<typeof postgres>;

export function connect(url: string): Sql {
  return postgres(url, { max: 2, onnotice: () => {} });
}

export class PgPaymentStore implements PaymentStore {
  constructor(private readonly sql: Sql) {}

  async createPayment(a: CreatePaymentArgs): Promise<PaymentRow> {
    try {
      const [row] = await this.sql`
        select * from public.create_payment(
          ${a.userId}::uuid, ${a.productId}::uuid, ${a.resourceId}::uuid, ${a.currency}::public.currency,
          ${a.channel}::public.payment_channel, ${a.provider}::public.payment_provider, ${a.msisdn},
          ${a.operator}::public.mm_operator, ${a.promoCode}, ${a.idempotencyKey}, ${a.ttlMinutes})`;
      return row as unknown as PaymentRow;
    } catch (e) {
      throw toHttpError(e);
    }
  }

  async markProcessing(id: string, ref: string): Promise<PaymentRow> {
    const [row] = await this.sql`select * from public.mark_payment_processing(${id}::uuid, ${ref})`;
    return row as unknown as PaymentRow;
  }

  async confirm(id: string, ref: string): Promise<void> {
    await this.sql`select public.confirm_payment(${id}::uuid, ${ref})`;
  }

  async fail(id: string, status: 'failed' | 'expired' | 'cancelled', reason: string): Promise<void> {
    await this.sql`select public.fail_payment(${id}::uuid, ${status}::public.payment_status, ${reason})`;
  }

  async recordEvent(provider: string, eventId: string, paymentId: string | null, payload: unknown): Promise<boolean> {
    const [row] = await this.sql`
      select public.record_payment_event(${provider}::public.payment_provider, ${eventId},
                                         ${paymentId}::uuid, ${this.sql.json(payload as never)}) as inserted`;
    return row.inserted === true;
  }

  async getPayment(id: string): Promise<PaymentRow | null> {
    const [row] = await this.sql`select * from public.payments where id = ${id}::uuid`;
    return (row as unknown as PaymentRow) ?? null;
  }

  async findByProviderReference(provider: string, ref: string): Promise<PaymentRow | null> {
    const [row] = await this.sql`
      select * from public.payments where provider = ${provider}::public.payment_provider and provider_reference = ${ref}`;
    return (row as unknown as PaymentRow) ?? null;
  }
}

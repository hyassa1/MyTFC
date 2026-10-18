// Agrégateur SIMULÉ, pour les tests et la démonstration (PAYMENT_PROVIDER=mock).
//
// Le comportement dépend des derniers chiffres du numéro mobile money :
//   ...01 → paiement accepté
//   ...02 → refusé (solde insuffisant)
//   ...03 → l'étudiant ne confirme jamais (délai dépassé)
//   ...04 → accepté, et l'agrégateur envoie la notification deux fois
//   ...05 → l'agrégateur est injoignable au lancement
//   autre → accepté
//
// En test, `settle()` simule la confirmation de l'étudiant sur son téléphone.

import type {
  InitiateRequest,
  InitiateResult,
  NormalizedEvent,
  NormalizedStatus,
  PaymentProvider,
} from './provider.ts';
import { WebhookRejected } from './provider.ts';

interface MockTx {
  paymentId: string;
  scenario: 'success' | 'insufficient_funds' | 'never' | 'double';
  state: 'pending' | 'succeeded' | 'failed';
}

export class MockProvider implements PaymentProvider {
  readonly name = 'mock' as const;
  readonly transactions = new Map<string, MockTx>();
  private counter = 0;

  constructor(private readonly webhookSecret = 'secret-de-test') {}

  initiate(req: InitiateRequest): Promise<InitiateResult> {
    const suffix = req.msisdn.slice(-2);
    if (suffix === '05') return Promise.resolve({ ok: false, reason: 'mock_unreachable' });
    const scenario = suffix === '02'
      ? 'insufficient_funds'
      : suffix === '03'
      ? 'never'
      : suffix === '04'
      ? 'double'
      : 'success';
    const ref = `MOCK-${++this.counter}-${req.paymentId.slice(0, 8)}`;
    this.transactions.set(ref, { paymentId: req.paymentId, scenario, state: 'pending' });
    return Promise.resolve({ ok: true, providerReference: ref });
  }

  /** Simule la réponse de l'étudiant (PIN saisi ou refus). */
  settle(ref: string): void {
    const tx = this.transactions.get(ref);
    if (!tx || tx.scenario === 'never') return;
    tx.state = tx.scenario === 'insufficient_funds' ? 'failed' : 'succeeded';
  }

  /** Construit la notification que l'agrégateur enverrait. */
  webhookRequest(ref: string, baseUrl = 'http://localhost/payment-webhook'): Request {
    const tx = this.transactions.get(ref)!;
    return new Request(`${baseUrl}?token=${this.webhookSecret}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        code: tx.state === 'succeeded' ? '0' : '1',
        reference: tx.paymentId,
        orderNumber: ref,
      }),
    });
  }

  /** Nombre de notifications à envoyer pour ce scénario. */
  webhookCount(ref: string): number {
    return this.transactions.get(ref)?.scenario === 'double' ? 2 : 1;
  }

  async parseWebhook(req: Request): Promise<NormalizedEvent> {
    if (new URL(req.url).searchParams.get('token') !== this.webhookSecret) {
      throw new WebhookRejected('invalid_webhook_token');
    }
    const payload = await req.json() as Record<string, unknown>;
    return {
      eventId: `${payload.orderNumber}:${payload.code}`,
      paymentId: payload.reference as string,
      providerReference: payload.orderNumber as string,
      payload,
    };
  }

  checkStatus(ref: string): Promise<NormalizedStatus> {
    const tx = this.transactions.get(ref);
    if (!tx || tx.state === 'pending') return Promise.resolve({ status: 'pending' });
    if (tx.state === 'failed') return Promise.resolve({ status: 'failed', reason: 'insufficient_funds' });
    return Promise.resolve({ status: 'succeeded', providerReference: ref });
  }
}

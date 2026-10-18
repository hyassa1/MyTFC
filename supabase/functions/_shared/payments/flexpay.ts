// Implémentation FlexPay (agrégateur mobile money en RDC : M-Pesa, Orange
// Money, Airtel Money, Afrimoney ; CDF et USD).
//
// API utilisée (d'après la documentation FlexPay et les SDK publics ; à
// RE-VÉRIFIER avec la documentation remise à l'ouverture du compte marchand,
// les URL sont donc configurables) :
//   POST {FLEXPAY_BASE_URL}/paymentService
//        Authorization: Bearer {FLEXPAY_TOKEN}
//        { merchant, type: 1, reference, phone, amount, currency, callbackUrl }
//     → { code: "0" si reçu, message, orderNumber }
//   GET  {FLEXPAY_CHECK_URL}/check/{orderNumber}
//     → { code, message, transaction: { reference, orderNumber, status: "0" réussi | "1" échoué, ... } }
//   Webhook : { code, reference, provider_reference, orderNumber, ... }
//
// Variables d'environnement (secrets Supabase, jamais dans l'app) :
//   FLEXPAY_MERCHANT, FLEXPAY_TOKEN, FLEXPAY_BASE_URL, FLEXPAY_CHECK_URL,
//   PAYMENT_WEBHOOK_SECRET (jeton ajouté à l'URL de rappel).

import {
  decimalAmount,
  type InitiateRequest,
  type InitiateResult,
  type NormalizedEvent,
  type NormalizedStatus,
  type PaymentProvider,
  WebhookRejected,
} from './provider.ts';

export interface FlexPayConfig {
  merchant: string;
  token: string;
  baseUrl: string;
  checkUrl: string;
  webhookSecret: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}

export const FLEXPAY_DEFAULT_BASE_URL = 'https://backend.flexpay.cd/api/rest/v1';
export const FLEXPAY_DEFAULT_CHECK_URL = 'https://apicheck.flexpaie.com/api/rest/v1';

export class FlexPayProvider implements PaymentProvider {
  readonly name = 'flexpay' as const;
  private readonly http: typeof fetch;

  constructor(private readonly config: FlexPayConfig) {
    this.http = config.fetch ?? fetch;
  }

  async initiate(req: InitiateRequest): Promise<InitiateResult> {
    let res: Response;
    try {
      res = await this.request(`${this.config.baseUrl}/paymentService`, {
        method: 'POST',
        body: JSON.stringify({
          merchant: this.config.merchant,
          type: 1, // 1 = mobile money
          reference: req.paymentId,
          phone: req.msisdn,
          amount: decimalAmount(req.amountMinor, req.currency),
          currency: req.currency,
          callbackUrl: req.callbackUrl,
        }),
      });
    } catch (e) {
      return { ok: false, reason: `flexpay_unreachable: ${(e as Error).message}` };
    }
    const body = await safeJson(res);
    if (res.ok && String(field(body, 'code')) === '0' && field(body, 'orderNumber')) {
      return { ok: true, providerReference: String(field(body, 'orderNumber')) };
    }
    return { ok: false, reason: String(field(body, 'message') ?? `flexpay_http_${res.status}`) };
  }

  async parseWebhook(req: Request): Promise<NormalizedEvent> {
    // FlexPay ne signe pas ses rappels : on exige notre jeton secret dans
    // l'URL, et on revérifie toujours l'état via checkStatus().
    const token = new URL(req.url).searchParams.get('token');
    if (!this.config.webhookSecret || token !== this.config.webhookSecret) {
      throw new WebhookRejected('invalid_webhook_token');
    }
    const payload = (await safeJson(req)) ?? {};
    const orderNumber = field(payload, 'orderNumber');
    const reference = field(payload, 'reference');
    if (!orderNumber && !reference) throw new WebhookRejected('missing_reference');
    const code = field(payload, 'code');
    return {
      // Un même rappel renvoyé plusieurs fois a le même identifiant.
      eventId: `${orderNumber ?? reference}:${code ?? ''}`,
      paymentId: reference ? String(reference) : undefined,
      providerReference: orderNumber ? String(orderNumber) : undefined,
      payload,
    };
  }

  async checkStatus(providerReference: string): Promise<NormalizedStatus> {
    let res: Response;
    try {
      res = await this.request(`${this.config.checkUrl}/check/${encodeURIComponent(providerReference)}`, {
        method: 'GET',
      });
    } catch {
      return { status: 'pending' }; // réseau : on réessaiera
    }
    const body = await safeJson(res);
    if (!res.ok || String(field(body, 'code')) !== '0') return { status: 'pending' };
    const tx = field(body, 'transaction') as Record<string, unknown> | undefined;
    const status = tx ? String(field(tx, 'status') ?? '') : '';
    if (status === '0') return { status: 'succeeded', providerReference };
    if (status === '1') return { status: 'failed', reason: String(field(body, 'message') ?? 'flexpay_failed') };
    return { status: 'pending' };
  }

  private async request(url: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs ?? 15_000);
    try {
      return await this.http(url, {
        ...init,
        signal: controller.signal,
        headers: { Authorization: `Bearer ${this.config.token}`, 'Content-Type': 'application/json' },
      });
    } finally {
      clearTimeout(timer);
    }
  }
}

/** Lecture d'un champ sans tenir compte de la casse (« Code » ou « code »). */
function field(obj: unknown, name: string): unknown {
  if (!obj || typeof obj !== 'object') return undefined;
  const lower = name.toLowerCase();
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    if (k.toLowerCase() === lower) return v;
  }
  return undefined;
}

async function safeJson(r: Request | Response): Promise<Record<string, unknown> | undefined> {
  try {
    return (await r.json()) as Record<string, unknown>;
  } catch {
    return undefined;
  }
}

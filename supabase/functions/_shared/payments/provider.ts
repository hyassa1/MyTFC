// Module de paiement abstrait.
//
// Tout le reste du code (fonctions payment-init, payment-webhook,
// payment-status) ne connaît que cette interface. Changer d'agrégateur =
// écrire une nouvelle classe qui l'implémente et changer la variable
// d'environnement PAYMENT_PROVIDER (voir factory.ts).

export type Currency = 'CDF' | 'USD';
export type MobileOperator = 'vodacom' | 'orange' | 'airtel' | 'afrimoney';

/** Demande de paiement envoyée à l'agrégateur. */
export interface InitiateRequest {
  /** Notre identifiant de paiement (payments.id), utilisé comme référence. */
  paymentId: string;
  /** Numéro mobile money au format 243XXXXXXXXX. */
  msisdn: string;
  operator?: MobileOperator;
  currency: Currency;
  /** Montant en unités mineures (×100), comme en base. */
  amountMinor: number;
  /** URL que l'agrégateur appellera avec le résultat. */
  callbackUrl: string;
  /** Libellé affiché à l'étudiant sur son téléphone, si l'agrégateur le permet. */
  description: string;
}

export type InitiateResult =
  | { ok: true; providerReference: string }
  | { ok: false; reason: string };

/** État d'une transaction chez l'agrégateur. */
export type NormalizedStatus =
  | { status: 'succeeded'; providerReference: string }
  | { status: 'failed'; reason: string }
  | { status: 'pending' };

/** Notification (webhook) traduite dans un format commun. */
export interface NormalizedEvent {
  /** Identifiant unique de l'événement, pour l'idempotence (payment_events). */
  eventId: string;
  /** Notre référence (payments.id), si l'agrégateur la renvoie. */
  paymentId?: string;
  /** Référence de l'agrégateur, si présente. */
  providerReference?: string;
  /** Contenu brut, journalisé tel quel. */
  payload: Record<string, unknown>;
}

export class WebhookRejected extends Error {}

export interface PaymentProvider {
  /** Nom stocké dans payments.provider. */
  readonly name: 'flexpay' | 'maxicash' | 'mock';

  /** Lance la demande de paiement (push USSD sur le téléphone de l'étudiant). */
  initiate(req: InitiateRequest): Promise<InitiateResult>;

  /**
   * Lit un webhook. Lève WebhookRejected s'il ne vient visiblement pas de
   * l'agrégateur. Le contenu n'est JAMAIS cru sur parole : l'état réel est
   * toujours relu avec checkStatus() avant de débloquer quoi que ce soit.
   */
  parseWebhook(req: Request): Promise<NormalizedEvent>;

  /** Interroge l'agrégateur sur l'état réel d'une transaction. */
  checkStatus(providerReference: string): Promise<NormalizedStatus>;
}

/** Montant décimal attendu par la plupart des agrégateurs (« 5800 », « 2.50 »). */
export function decimalAmount(amountMinor: number, currency: Currency): string {
  return currency === 'CDF' ? String(Math.round(amountMinor / 100)) : (amountMinor / 100).toFixed(2);
}

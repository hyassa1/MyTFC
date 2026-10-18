// Logique de la page de paiement, séparée de l'affichage pour être testée.

export type PaymentStatus = 'pending' | 'processing' | 'succeeded' | 'failed' | 'expired' | 'cancelled';

export interface PublicPayment {
  id: string;
  status: PaymentStatus;
  currency: string;
  amount_net_minor: number;
  failure_reason?: string | null;
  expires_at?: string | null;
}

export interface Offer {
  id: string;
  code: string;
  name: string;
  description: string | null;
  feature: string;
  requires_resource: boolean;
  prices: Record<string, number>;
}

/** Offres actives avec au moins un prix, dans l'ordre de l'admin. */
export function buildOffers(
  products: Array<Omit<Offer, 'prices'> & { is_active: boolean; position: number }>,
  prices: Array<{ product_id: string; currency: string; amount_minor: number }>,
): Offer[] {
  return products
    .filter((p) => p.is_active)
    .sort((a, b) => a.position - b.position)
    .map((p) => ({
      id: p.id, code: p.code, name: p.name, description: p.description, feature: p.feature,
      requires_resource: p.requires_resource,
      prices: Object.fromEntries(prices.filter((x) => x.product_id === p.id).map((x) => [x.currency, x.amount_minor])),
    }))
    .filter((o) => Object.keys(o.prices).length > 0);
}

/** Délai de suivi après l'expiration : un succès tardif reste possible. */
export const GRACE_MS = 2 * 60 * 1000;

/** Que faire après une réponse de payment-status ? */
export function nextStep(p: PublicPayment, now: number): 'wait' | 'success' | 'failure' | 'timeout' {
  switch (p.status) {
    case 'succeeded':
      return 'success';
    case 'failed':
    case 'cancelled':
      return 'failure';
    case 'expired': {
      const deadline = (p.expires_at ? Date.parse(p.expires_at) : now) + GRACE_MS;
      return now > deadline ? 'timeout' : 'wait';
    }
    default:
      return 'wait';
  }
}

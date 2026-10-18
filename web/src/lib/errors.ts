// Messages en français pour les codes d'erreur du serveur.

const MESSAGES: Record<string, string> = {
  insufficient_funds: 'Solde insuffisant sur ton compte mobile money.',
  timeout: 'Tu n\'as pas confirmé le paiement à temps. Aucun montant n\'a été débité.',
  invalid_msisdn: 'Numéro mobile money invalide.',
  resource_required: 'Choisis d\'abord le modèle à acheter.',
  promo_invalid: 'Code promo invalide.',
  promo_expired: 'Ce code promo a expiré.',
  promo_not_started: 'Ce code promo n\'est pas encore valable.',
  promo_exhausted: 'Ce code promo a atteint son nombre maximal d\'utilisations.',
  promo_not_applicable: 'Ce code promo ne s\'applique pas à cette offre.',
  product_not_found: 'Cette offre n\'est plus disponible.',
  price_not_found: 'Cette offre n\'est plus disponible.',
  not_authenticated: 'Ta session a expiré. Reconnecte-toi.',
  not_admin: 'Ce compte n\'a pas accès à l\'administration.',
};

export function errorMessage(code: string | null | undefined): string {
  if (!code) return 'L\'opération n\'a pas abouti.';
  if (MESSAGES[code]) return MESSAGES[code];
  if (code.includes('unreachable')) return 'Le service de paiement ne répond pas. Aucun montant n\'a été débité.';
  return 'L\'opération n\'a pas abouti. Réessaie dans un instant.';
}

/** Extrait le code d'erreur d'une FunctionsHttpError de supabase-js. */
export async function functionErrorCode(error: unknown): Promise<string | null> {
  const ctx = (error as { context?: Response })?.context;
  if (ctx && typeof ctx.json === 'function') {
    try {
      const body = (await ctx.json()) as { error?: string };
      return body.error ?? null;
    } catch {
      return null;
    }
  }
  return null;
}

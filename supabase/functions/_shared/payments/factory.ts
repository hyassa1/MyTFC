// Choix de l'agrégateur selon PAYMENT_PROVIDER (flexpay | mock).
// Ajouter un agrégateur (ex. MaxiCash) : une classe qui implémente
// PaymentProvider + un cas ici. Rien d'autre ne change.

import { FLEXPAY_DEFAULT_BASE_URL, FLEXPAY_DEFAULT_CHECK_URL, FlexPayProvider } from './flexpay.ts';
import { MockProvider } from './mock.ts';
import type { PaymentProvider } from './provider.ts';

let cached: PaymentProvider | undefined;

export function providerFromEnv(env: (k: string) => string | undefined = (k) => Deno.env.get(k)): PaymentProvider {
  if (cached) return cached;
  const name = env('PAYMENT_PROVIDER') ?? 'mock';
  switch (name) {
    case 'flexpay': {
      const merchant = env('FLEXPAY_MERCHANT');
      const token = env('FLEXPAY_TOKEN');
      const webhookSecret = env('PAYMENT_WEBHOOK_SECRET');
      if (!merchant || !token || !webhookSecret) {
        throw new Error('FLEXPAY_MERCHANT, FLEXPAY_TOKEN et PAYMENT_WEBHOOK_SECRET sont obligatoires');
      }
      cached = new FlexPayProvider({
        merchant,
        token,
        webhookSecret,
        baseUrl: env('FLEXPAY_BASE_URL') ?? FLEXPAY_DEFAULT_BASE_URL,
        checkUrl: env('FLEXPAY_CHECK_URL') ?? FLEXPAY_DEFAULT_CHECK_URL,
      });
      return cached;
    }
    case 'mock':
      // Garde-fou : jamais d'agrégateur simulé en production par erreur.
      if (env('MONTFC_ENV') === 'production') throw new Error('PAYMENT_PROVIDER=mock interdit en production');
      cached = new MockProvider(env('PAYMENT_WEBHOOK_SECRET') ?? 'secret-de-test');
      return cached;
    default:
      throw new Error(`Agrégateur inconnu : ${name}`);
  }
}

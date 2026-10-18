// Assemblage de production : base Supabase (service_role) + agrégateur choisi
// par PAYMENT_PROVIDER. URL de rappel : PAYMENT_CALLBACK_URL, ou l'URL de la
// fonction payment-webhook déduite de SUPABASE_URL, avec le jeton secret.

import { adminClient, userFromToken } from '../supabase.ts';
import { providerFromEnv } from './factory.ts';
import { PaymentService } from './service.ts';
import { SupabasePaymentStore } from './store.ts';
import type { PaymentHandlerDeps } from './handlers.ts';

export function productionDeps(): PaymentHandlerDeps {
  const admin = adminClient();
  const base = Deno.env.get('PAYMENT_CALLBACK_URL') ??
    `${Deno.env.get('SUPABASE_URL')}/functions/v1/payment-webhook`;
  const secret = Deno.env.get('PAYMENT_WEBHOOK_SECRET') ?? '';
  const callbackUrl = `${base}?token=${encodeURIComponent(secret)}`;
  const ttl = Number(Deno.env.get('PAYMENT_TTL_MINUTES') ?? '10');

  return {
    service: new PaymentService(new SupabasePaymentStore(admin), providerFromEnv(), { callbackUrl, ttlMinutes: ttl }),
    userFromToken: (jwt) => userFromToken(admin, jwt),
  };
}

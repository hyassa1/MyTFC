// Gestionnaires HTTP des trois fonctions de paiement. Les dépendances sont
// injectées pour pouvoir tester le flux complet avec un agrégateur simulé.

import { bearerToken, handle, json, readJson } from '../http.ts';
import type { PaymentService, StartPaymentInput } from './service.ts';

export interface PaymentHandlerDeps {
  service: PaymentService;
  userFromToken(jwt: string): Promise<{ id: string }>;
}

/** POST /payment-init : lance un paiement mobile money (utilisateur connecté). */
export function createPaymentInitHandler(deps: PaymentHandlerDeps) {
  return handle(async (req) => {
    const user = await deps.userFromToken(bearerToken(req));
    const input = await readJson<StartPaymentInput>(req);
    return json({ payment: await deps.service.start(user.id, input) });
  });
}

/** POST /payment-status : état d'un paiement (utilisateur connecté, propriétaire). */
export function createPaymentStatusHandler(deps: PaymentHandlerDeps) {
  return handle(async (req) => {
    const user = await deps.userFromToken(bearerToken(req));
    const { payment_id } = await readJson<{ payment_id: string }>(req);
    return json({ payment: await deps.service.status(user.id, payment_id) });
  });
}

/** POST /payment-webhook : notification de l'agrégateur (sans jeton utilisateur). */
export function createPaymentWebhookHandler(deps: Pick<PaymentHandlerDeps, 'service'>) {
  return handle(async (req) => {
    const { status, body } = await deps.service.handleWebhook(req);
    return json(body, status);
  });
}

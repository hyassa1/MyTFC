// Edge Function payment-webhook : appelée par l'agrégateur, SANS jeton
// utilisateur (verify_jwt = false dans config.toml). L'authenticité est
// contrôlée par le jeton secret de l'URL, et l'état est toujours revérifié
// chez l'agrégateur avant tout déblocage.
import { createPaymentWebhookHandler } from '../_shared/payments/handlers.ts';
import { productionDeps } from '../_shared/payments/runtime.ts';

Deno.serve(createPaymentWebhookHandler(productionDeps()));

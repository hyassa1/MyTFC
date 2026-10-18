// Edge Function payment-init : voir _shared/payments/service.ts (start).
import { createPaymentInitHandler } from '../_shared/payments/handlers.ts';
import { productionDeps } from '../_shared/payments/runtime.ts';

Deno.serve(createPaymentInitHandler(productionDeps()));

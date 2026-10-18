// Edge Function payment-status : voir _shared/payments/service.ts (status).
import { createPaymentStatusHandler } from '../_shared/payments/handlers.ts';
import { productionDeps } from '../_shared/payments/runtime.ts';

Deno.serve(createPaymentStatusHandler(productionDeps()));

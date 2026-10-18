import { assertEquals, assertRejects } from '@std/assert';
import { FlexPayProvider } from './flexpay.ts';
import { WebhookRejected } from './provider.ts';

function provider(responder: (url: string, init: RequestInit) => Response) {
  const calls: { url: string; init: RequestInit }[] = [];
  const p = new FlexPayProvider({
    merchant: 'MONTFC',
    token: 'jeton-api',
    baseUrl: 'https://flexpay.test/api/rest/v1',
    checkUrl: 'https://check.flexpay.test/api/rest/v1',
    webhookSecret: 'secret',
    fetch: ((url: string, init: RequestInit) => {
      calls.push({ url, init });
      return Promise.resolve(responder(url, init));
    }) as typeof fetch,
  });
  return { p, calls };
}

const jsonResponse = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

Deno.test('FlexPay : la demande de paiement envoie le bon contenu', async () => {
  const { p, calls } = provider(() => jsonResponse({ code: '0', message: 'ok', orderNumber: 'ORD-1' }));
  const r = await p.initiate({
    paymentId: 'pay-1',
    msisdn: '243812345678',
    currency: 'CDF',
    amountMinor: 580000,
    callbackUrl: 'https://cb.test?token=secret',
    description: 'MonTFC',
  });
  assertEquals(r, { ok: true, providerReference: 'ORD-1' });
  assertEquals(calls[0].url, 'https://flexpay.test/api/rest/v1/paymentService');
  assertEquals((calls[0].init.headers as Record<string, string>).Authorization, 'Bearer jeton-api');
  assertEquals(JSON.parse(calls[0].init.body as string), {
    merchant: 'MONTFC',
    type: 1,
    reference: 'pay-1',
    phone: '243812345678',
    amount: '5800',
    currency: 'CDF',
    callbackUrl: 'https://cb.test?token=secret',
  });
});

Deno.test('FlexPay : montant USD avec deux décimales', async () => {
  const { p, calls } = provider(() => jsonResponse({ code: '0', orderNumber: 'ORD-2' }));
  await p.initiate({ paymentId: 'x', msisdn: '243', currency: 'USD', amountMinor: 900, callbackUrl: '', description: '' });
  assertEquals(JSON.parse(calls[0].init.body as string).amount, '9.00');
});

Deno.test('FlexPay : refus de la demande → échec avec le message', async () => {
  const { p } = provider(() => jsonResponse({ code: '1', message: 'Numéro invalide' }));
  const r = await p.initiate({ paymentId: 'x', msisdn: '243', currency: 'USD', amountMinor: 100, callbackUrl: '', description: '' });
  assertEquals(r, { ok: false, reason: 'Numéro invalide' });
});

Deno.test('FlexPay : statut 0 = réussi, 1 = échoué, autre = en attente', async () => {
  for (const [status, expected] of [['0', 'succeeded'], ['1', 'failed'], ['2', 'pending']] as const) {
    const { p, calls } = provider(() => jsonResponse({ code: '0', transaction: { status, orderNumber: 'ORD-1' } }));
    assertEquals((await p.checkStatus('ORD-1')).status, expected);
    assertEquals(calls[0].url, 'https://check.flexpay.test/api/rest/v1/check/ORD-1');
  }
});

Deno.test('FlexPay : erreur réseau ou HTTP au contrôle → en attente (on réessaiera)', async () => {
  const { p } = provider(() => jsonResponse({}, 500));
  assertEquals((await p.checkStatus('ORD-1')).status, 'pending');
});

Deno.test('FlexPay : webhook lu sans tenir compte de la casse, jeton secret obligatoire', async () => {
  const { p } = provider(() => jsonResponse({}));
  const ok = await p.parseWebhook(new Request('https://x/payment-webhook?token=secret', {
    method: 'POST',
    body: JSON.stringify({ Code: '0', Reference: 'pay-1', orderNumber: 'ORD-1', Provider_reference: 'MP123' }),
  }));
  assertEquals(ok.paymentId, 'pay-1');
  assertEquals(ok.providerReference, 'ORD-1');
  assertEquals(ok.eventId, 'ORD-1:0');

  await assertRejects(
    () => p.parseWebhook(new Request('https://x/payment-webhook?token=faux', { method: 'POST', body: '{}' })),
    WebhookRejected,
  );
});

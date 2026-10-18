// Tests du flux de paiement complet, avec l'agrégateur SIMULÉ et la vraie
// base (fonctions SQL de supabase/migrations).
//
// Lancement : deno task test:db   (démarre un PostgreSQL local jetable)
// Sans TEST_DATABASE_URL, ces tests sont ignorés.

import { assert, assertEquals } from '@std/assert';
import {
  createPaymentInitHandler,
  createPaymentStatusHandler,
  createPaymentWebhookHandler,
} from '../_shared/payments/handlers.ts';
import { MockProvider } from '../_shared/payments/mock.ts';
import { PaymentService } from '../_shared/payments/service.ts';
import { connect, PgPaymentStore, type Sql } from './pg_store.ts';

const DB_URL = Deno.env.get('TEST_DATABASE_URL');

// Identifiants des données de démonstration (supabase/seed.sql).
const PACK = '00000000-0000-4000-8000-000000000504';
const COVER = '00000000-0000-4000-8000-000000000501';
const DOC_TEMPLATE = '00000000-0000-4000-8000-000000000502';
const MEMOIRE = '00000000-0000-4000-8000-000000000401';

interface Ctx {
  sql: Sql;
  provider: MockProvider;
  init: (req: Request) => Promise<Response>;
  status: (req: Request) => Promise<Response>;
  webhook: (req: Request) => Promise<Response>;
  userId: string;
  token: string;
}

let userCounter = 0;

async function setup(sql: Sql): Promise<Ctx> {
  const provider = new MockProvider('secret-de-test');
  const service = new PaymentService(new PgPaymentStore(sql), provider, {
    callbackUrl: 'http://localhost/payment-webhook?token=secret-de-test',
    ttlMinutes: 10,
  });
  // Chaque test a son propre étudiant ; le « jeton » est simplement son id.
  const [user] = await sql`
    insert into auth.users (phone) values (${'2438100' + String(++userCounter).padStart(5, '0') + Date.now() % 1000})
    returning id`;
  const users = new Set<string>([user.id]);
  const userFromToken = (jwt: string) =>
    users.has(jwt) ? Promise.resolve({ id: jwt }) : Promise.reject(new Error('jeton invalide'));
  return {
    sql,
    provider,
    init: createPaymentInitHandler({ service, userFromToken }),
    status: createPaymentStatusHandler({ service, userFromToken }),
    webhook: createPaymentWebhookHandler({ service }),
    userId: user.id,
    token: user.id,
  };
}

function post(token: string | null, body: unknown): Request {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request('http://localhost/fn', { method: 'POST', headers, body: JSON.stringify(body) });
}

async function startPayment(c: Ctx, body: Record<string, unknown>) {
  const res = await c.init(post(c.token, {
    product_id: PACK,
    currency: 'USD',
    idempotency_key: crypto.randomUUID(),
    ...body,
  }));
  return { res, json: await res.json() };
}

async function statusOf(c: Ctx, paymentId: string, token = c.token) {
  const res = await c.status(post(token, { payment_id: paymentId }));
  return { res, json: await res.json() };
}

async function refOf(c: Ctx, paymentId: string): Promise<string> {
  const [row] = await c.sql`select provider_reference from public.payments where id = ${paymentId}`;
  return row.provider_reference;
}

async function countEntitlements(c: Ctx): Promise<number> {
  const [row] = await c.sql`select count(*)::int as n from public.entitlements where user_id = ${c.userId}`;
  return row.n;
}

function dbTest(name: string, fn: (c: Ctx) => Promise<void>) {
  Deno.test({
    name,
    ignore: !DB_URL,
    sanitizeOps: false,
    sanitizeResources: false,
    async fn() {
      const sql = connect(DB_URL!);
      try {
        await fn(await setup(sql));
      } finally {
        await sql.end();
      }
    },
  });
}

// -----------------------------------------------------------------------------

dbTest('paiement réussi : en attente → confirmation sur le téléphone → webhook → accès débloqué', async (c) => {
  const { res, json } = await startPayment(c, { msisdn: '0812345601', operator: 'vodacom' });
  assertEquals(res.status, 200);
  assertEquals(json.payment.status, 'processing');
  assertEquals(json.payment.amount_net_minor, 1000);

  // Tant que l'étudiant n'a pas confirmé : toujours en attente.
  assertEquals((await statusOf(c, json.payment.id)).json.payment.status, 'processing');
  assertEquals(await countEntitlements(c), 0);

  const ref = await refOf(c, json.payment.id);
  c.provider.settle(ref);
  const hook = await c.webhook(c.provider.webhookRequest(ref));
  assertEquals(hook.status, 200);

  assertEquals((await statusOf(c, json.payment.id)).json.payment.status, 'succeeded');
  assertEquals(await countEntitlements(c), 1);
});

dbTest('double notification de l\'agrégateur : un seul droit, une seule commission', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0812345604', promo_code: 'DEMO10' });
  assertEquals(json.payment.amount_net_minor, 900, 'code promo DEMO10 : 10 % de réduction');
  const ref = await refOf(c, json.payment.id);
  c.provider.settle(ref);
  assertEquals(c.provider.webhookCount(ref), 2);

  const first = await (await c.webhook(c.provider.webhookRequest(ref))).json();
  const second = await (await c.webhook(c.provider.webhookRequest(ref))).json();
  assertEquals(first.status, 'succeeded');
  assertEquals(second.duplicate, true);

  assertEquals(await countEntitlements(c), 1);
  const [com] = await c.sql`select count(*)::int as n, sum(amount_minor)::int as total
                              from public.commissions where payment_id = ${json.payment.id}`;
  assertEquals(com.n, 1);
  assertEquals(com.total, 180, 'commission de 20 % sur 9,00 USD');
});

dbTest('échec (solde insuffisant) : statut « failed », aucun accès', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0842345602', currency: 'CDF', product_id: COVER });
  assertEquals(json.payment.amount_net_minor, 580000);
  const ref = await refOf(c, json.payment.id);
  c.provider.settle(ref);
  await c.webhook(c.provider.webhookRequest(ref));

  const st = (await statusOf(c, json.payment.id)).json.payment;
  assertEquals(st.status, 'failed');
  assertEquals(st.failure_reason, 'insufficient_funds');
  assertEquals(await countEntitlements(c), 0);
});

dbTest('délai dépassé : l\'étudiant ne confirme pas → « expired » par la tâche planifiée', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0992345603' });
  await c.sql`update public.payments set expires_at = now() - interval '1 minute' where id = ${json.payment.id}`;
  await c.sql`select public.expire_stale_payments()`;

  const st = (await statusOf(c, json.payment.id)).json.payment;
  assertEquals(st.status, 'expired');
  assertEquals(await countEntitlements(c), 0);
});

dbTest('succès tardif après le délai : l\'étudiant a payé, il est débloqué', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0812345601' });
  await c.sql`update public.payments set expires_at = now() - interval '1 minute' where id = ${json.payment.id}`;
  await c.sql`select public.expire_stale_payments()`;
  c.provider.settle(await refOf(c, json.payment.id));

  assertEquals((await statusOf(c, json.payment.id)).json.payment.status, 'succeeded');
  assertEquals(await countEntitlements(c), 1);
});

dbTest('notification perdue : le suivi de l\'application va chercher l\'état et débloque', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0812345601' });
  c.provider.settle(await refOf(c, json.payment.id));
  // Aucun webhook n'arrive.
  assertEquals((await statusOf(c, json.payment.id)).json.payment.status, 'succeeded');
  assertEquals(await countEntitlements(c), 1);
});

dbTest('agrégateur injoignable : paiement marqué en échec, rien n\'est débité', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0812345605' });
  assertEquals(json.payment.status, 'failed');
  assertEquals(json.payment.failure_reason, 'mock_unreachable');
});

dbTest('double clic (même clé) : un seul paiement et une seule demande à l\'agrégateur', async (c) => {
  const key = crypto.randomUUID();
  const a = await startPayment(c, { msisdn: '0812345601', idempotency_key: key });
  const b = await startPayment(c, { msisdn: '0812345601', idempotency_key: key });
  assertEquals(a.json.payment.id, b.json.payment.id);
  assertEquals(c.provider.transactions.size, 1);
});

dbTest('achat d\'un modèle précis : seul ce modèle est débloqué', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0812345601', product_id: DOC_TEMPLATE, resource_id: MEMOIRE });
  const ref = await refOf(c, json.payment.id);
  c.provider.settle(ref);
  await c.webhook(c.provider.webhookRequest(ref));
  const [ent] = await c.sql`select feature, resource_id from public.entitlements where user_id = ${c.userId}`;
  assertEquals(ent.feature, 'doc_template');
  assertEquals(ent.resource_id, MEMOIRE);
});

dbTest('erreurs de saisie : messages précis, aucun paiement créé', async (c) => {
  const bad = await startPayment(c, { msisdn: '12345' });
  assertEquals(bad.res.status, 400);
  assertEquals(bad.json.error, 'invalid_msisdn');

  const promo = await startPayment(c, { msisdn: '0812345601', promo_code: 'FAUX' });
  assertEquals(promo.json.error, 'promo_invalid');

  const resource = await startPayment(c, { msisdn: '0812345601', product_id: DOC_TEMPLATE });
  assertEquals(resource.json.error, 'resource_required');

  const [row] = await c.sql`select count(*)::int as n from public.payments where user_id = ${c.userId}`;
  assertEquals(row.n, 0);
});

dbTest('sécurité : webhook sans le jeton secret refusé ; paiement d\'un autre invisible', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0812345601' });
  const ref = await refOf(c, json.payment.id);
  c.provider.settle(ref);

  const forged = new Request('http://localhost/payment-webhook?token=faux', {
    method: 'POST',
    body: JSON.stringify({ code: '0', reference: json.payment.id, orderNumber: ref }),
  });
  assertEquals((await c.webhook(forged)).status, 401);

  const other = await setup(c.sql);
  const spy = await statusOf(other, json.payment.id);
  assertEquals(spy.res.status, 404);

  const anonymous = await c.status(post(null, { payment_id: json.payment.id }));
  assertEquals(anonymous.status, 401);
});

dbTest('webhook falsifié avec le bon jeton : l\'état est revérifié, rien n\'est débloqué', async (c) => {
  const { json } = await startPayment(c, { msisdn: '0992345603' }); // l'étudiant ne paie jamais
  const ref = await refOf(c, json.payment.id);
  const fake = new Request('http://localhost/payment-webhook?token=secret-de-test', {
    method: 'POST',
    body: JSON.stringify({ code: '0', reference: json.payment.id, orderNumber: ref }),
  });
  const res = await (await c.webhook(fake)).json();
  assert(res.status !== 'succeeded');
  assertEquals(await countEntitlements(c), 0);
});

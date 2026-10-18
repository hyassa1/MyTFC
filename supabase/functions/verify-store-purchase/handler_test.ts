import { assertEquals } from '@std/assert';
import type { PlayProductPurchase } from '../_shared/stores/google_play.ts';
import { createVerifyStorePurchaseHandler, type VerifyStoreDeps } from './handler.ts';

const USER = '11111111-1111-4111-8111-111111111111';
const TEMPLATE = '00000000-0000-4000-8000-000000000401';

function fakeDeps(purchases: Record<string, PlayProductPurchase>, opts: Partial<VerifyStoreDeps> = {}) {
  const grants: { reference: string; resourceId: string | null }[] = [];
  const deps: VerifyStoreDeps = {
    acceptTestPurchases: false,
    play: { getProductPurchase: (_p, token) => Promise.resolve(purchases[token] ?? null) },
    userFromToken: () => Promise.resolve({ id: USER }),
    productByPlayId: (id) =>
      Promise.resolve(
        id === 'montfc_pack_finaliste'
          ? { id: 'p-pack', feature: 'all', requires_resource: false, currency: 'USD', amount_minor: 1000 }
          : id === 'montfc_doc_template'
          ? {
            id: 'p-doc',
            feature: 'doc_template',
            requires_resource: true,
            currency: 'USD',
            amount_minor: 300,
          }
          : null,
      ),
    resourceExists: (_f, id) => Promise.resolve(id === TEMPLATE),
    grant(input) {
      // Comme grant_store_purchase : idempotent sur la référence.
      if (!grants.some((g) => g.reference === input.reference)) {
        grants.push({ reference: input.reference, resourceId: input.resourceId });
      }
      return Promise.resolve({ ok: true });
    },
    ...opts,
  };
  return { deps, grants };
}

function call(deps: VerifyStoreDeps, body: unknown) {
  return createVerifyStorePurchaseHandler(deps)(
    new Request('http://localhost/verify-store-purchase', {
      method: 'POST',
      headers: { Authorization: 'Bearer jeton', 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }),
  );
}

const ok = (extra: Partial<PlayProductPurchase> = {}): PlayProductPurchase => ({
  purchaseState: 0,
  obfuscatedExternalAccountId: USER,
  orderId: 'GPA.1234',
  ...extra,
});

Deno.test("achat Google confirmé : droit créé une seule fois même si l'app renvoie le jeton", async () => {
  const { deps, grants } = fakeDeps({ 'tok-1': ok() });
  const body = { platform: 'android', play_product_id: 'montfc_pack_finaliste', purchase_token: 'tok-1' };
  assertEquals((await call(deps, body)).status, 200);
  assertEquals((await call(deps, body)).status, 200);
  assertEquals(grants.length, 1);
});

Deno.test("jeton inconnu de Google (falsifié) : refusé, rien n'est débloqué", async () => {
  const { deps, grants } = fakeDeps({});
  const res = await call(deps, {
    platform: 'android',
    play_product_id: 'montfc_pack_finaliste',
    purchase_token: 'x',
  });
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, 'invalid_purchase');
  assertEquals(grants.length, 0);
});

Deno.test('achat fait depuis un autre compte : 403', async () => {
  const { deps, grants } = fakeDeps({ t: ok({ obfuscatedExternalAccountId: 'quelqu-un-d-autre' }) });
  const res = await call(deps, {
    platform: 'android',
    play_product_id: 'montfc_pack_finaliste',
    purchase_token: 't',
  });
  assertEquals(res.status, 403);
  assertEquals(grants.length, 0);
});

Deno.test('paiement différé (en attente chez Google) : 202, pas encore de droit', async () => {
  const { deps, grants } = fakeDeps({ t: ok({ purchaseState: 2 }) });
  const res = await call(deps, {
    platform: 'android',
    play_product_id: 'montfc_pack_finaliste',
    purchase_token: 't',
  });
  assertEquals(res.status, 202);
  assertEquals((await res.json()).status, 'pending');
  assertEquals(grants.length, 0);
});

Deno.test('achat annulé ou achat de test en production : refusé', async () => {
  const { deps } = fakeDeps({ a: ok({ purchaseState: 1 }), b: ok({ purchaseType: 0 }) });
  const base = { platform: 'android', play_product_id: 'montfc_pack_finaliste' };
  assertEquals(
    (await (await call(deps, { ...base, purchase_token: 'a' })).json()).error,
    'purchase_cancelled',
  );
  assertEquals(
    (await (await call(deps, { ...base, purchase_token: 'b' })).json()).error,
    'test_purchase_rejected',
  );
  const { deps: testing, grants } = fakeDeps({ b: ok({ purchaseType: 0 }) }, { acceptTestPurchases: true });
  assertEquals((await call(testing, { ...base, purchase_token: 'b' })).status, 200);
  assertEquals(grants.length, 1);
});

Deno.test('modèle précis : identifiant pris dans obfuscatedExternalProfileId et vérifié', async () => {
  const { deps, grants } = fakeDeps({
    good: ok({ obfuscatedExternalProfileId: TEMPLATE }),
    missing: ok(),
    unknown: ok({ obfuscatedExternalProfileId: '00000000-0000-4000-8000-000000000999' }),
  });
  const base = { platform: 'android', play_product_id: 'montfc_doc_template' };
  assertEquals((await call(deps, { ...base, purchase_token: 'good' })).status, 200);
  assertEquals(grants[0].resourceId, TEMPLATE);
  assertEquals(
    (await (await call(deps, { ...base, purchase_token: 'missing' })).json()).error,
    'invalid_resource',
  );
  assertEquals(
    (await (await call(deps, { ...base, purchase_token: 'unknown' })).json()).error,
    'invalid_resource',
  );
  assertEquals(grants.length, 1);
});

Deno.test('produit Play inconnu : 404', async () => {
  const { deps } = fakeDeps({ t: ok() });
  const res = await call(deps, { platform: 'android', play_product_id: 'autre', purchase_token: 't' });
  assertEquals(res.status, 404);
});

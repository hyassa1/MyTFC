import { assert, assertEquals } from '@std/assert';
import { GooglePlayApi, signServiceAccountJwt } from './google_play.ts';

async function testAccount() {
  const pair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let s = '';
  for (const b of der) s += String.fromCharCode(b);
  // Format du fichier JSON de Google : PEM avec des « \n » échappés.
  const pem = `-----BEGIN PRIVATE KEY-----\\n${
    btoa(s).match(/.{1,64}/g)!.join('\\n')
  }\\n-----END PRIVATE KEY-----\\n`;
  return {
    sa: { client_email: 'montfc@test.iam.gserviceaccount.com', private_key: pem },
    publicKey: pair.publicKey,
  };
}

function fromBase64Url(s: string): Uint8Array<ArrayBuffer> {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

Deno.test('assertion JWT du compte de service : signature RS256 valide et bons champs', async () => {
  const { sa, publicKey } = await testAccount();
  const jwt = await signServiceAccountJwt(sa, 1_800_000_000);
  const [h, c, sig] = jwt.split('.');
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    publicKey,
    fromBase64Url(sig),
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert(valid);
  const claims = JSON.parse(new TextDecoder().decode(fromBase64Url(c)));
  assertEquals(claims.iss, sa.client_email);
  assertEquals(claims.scope, 'https://www.googleapis.com/auth/androidpublisher');
  assertEquals(claims.exp - claims.iat, 3600);
});

Deno.test('API Play : jeton OAuth réutilisé, achat lu, jeton inconnu = null', async () => {
  const { sa } = await testAccount();
  const calls: string[] = [];
  const fakeFetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push(url);
    if (url.startsWith('https://oauth2.googleapis.com/token')) {
      return Promise.resolve(Response.json({ access_token: 'acces', expires_in: 3600 }));
    }
    assertEquals(new Headers(init?.headers).get('Authorization'), 'Bearer acces');
    if (url.endsWith('/tokens/bon')) {
      return Promise.resolve(Response.json({ purchaseState: 0, obfuscatedExternalAccountId: 'u1' }));
    }
    return Promise.resolve(new Response('{}', { status: 400 }));
  };
  const api = new GooglePlayApi(sa, 'cd.montfc.app', fakeFetch as typeof fetch);
  assertEquals(
    (await api.getProductPurchase('montfc_pack_finaliste', 'bon'))?.obfuscatedExternalAccountId,
    'u1',
  );
  assertEquals(await api.getProductPurchase('montfc_pack_finaliste', 'faux'), null);
  assertEquals(calls.filter((u) => u.includes('oauth2')).length, 1);
  assert(
    calls[1].includes('/applications/cd.montfc.app/purchases/products/montfc_pack_finaliste/tokens/bon'),
  );
});

// Vérification des achats Google Play (variante « store » de l'application).
//
// L'application ne fait jamais foi : elle transmet le jeton d'achat, le
// serveur interroge l'API Google Play Developer avec un compte de service et
// ne débloque que si Google confirme l'achat ET que l'achat a été fait depuis
// ce compte MonTFC (obfuscatedExternalAccountId = identifiant utilisateur).
//
// Variables d'environnement (serveur uniquement) :
//   GOOGLE_PLAY_SERVICE_ACCOUNT  JSON complet de la clé du compte de service
//   GOOGLE_PLAY_PACKAGE_NAME     cd.montfc.app par défaut

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

/** Réponse utile de purchases.products.get (champs documentés par Google). */
export interface PlayProductPurchase {
  /** 0 = acheté, 1 = annulé, 2 = en attente (paiement différé). */
  purchaseState: number;
  /** 0 = pas encore consommé, 1 = consommé. */
  consumptionState?: number;
  /** 0 = achat de test (testeurs de licence), absent pour un vrai achat. */
  purchaseType?: number;
  orderId?: string;
  obfuscatedExternalAccountId?: string;
  obfuscatedExternalProfileId?: string;
  regionCode?: string;
}

export interface PlayApi {
  getProductPurchase(productId: string, token: string): Promise<PlayProductPurchase | null>;
}

type Fetch = typeof fetch;

function base64Url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes;
  let s = '';
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\\n|\s/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

/** Assertion JWT signée RS256 pour obtenir un jeton OAuth du compte de service. */
export async function signServiceAccountJwt(sa: ServiceAccount, nowSeconds = Math.floor(Date.now() / 1000)) {
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64Url(JSON.stringify({
    iss: sa.client_email,
    scope: SCOPE,
    aud: sa.token_uri ?? TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const input = `${header}.${claims}`;
  const key = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(input));
  return `${input}.${base64Url(new Uint8Array(signature))}`;
}

export class GooglePlayApi implements PlayApi {
  private token?: { value: string; expiresAt: number };

  constructor(
    private readonly sa: ServiceAccount,
    private readonly packageName: string,
    private readonly fetchFn: Fetch = fetch,
  ) {}

  static fromEnv(): GooglePlayApi {
    const raw = Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT');
    if (!raw) throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT manquant');
    return new GooglePlayApi(
      JSON.parse(raw) as ServiceAccount,
      Deno.env.get('GOOGLE_PLAY_PACKAGE_NAME') ?? 'cd.montfc.app',
    );
  }

  private async accessToken(): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now() + 60_000) return this.token.value;
    const res = await this.fetchFn(this.sa.token_uri ?? TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: await signServiceAccountJwt(this.sa),
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) throw new Error(`Google OAuth ${res.status}: ${await res.text()}`);
    const body = await res.json() as { access_token: string; expires_in: number };
    this.token = { value: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
    return body.access_token;
  }

  async getProductPurchase(productId: string, token: string): Promise<PlayProductPurchase | null> {
    const url = `${API}/applications/${encodeURIComponent(this.packageName)}/purchases/products/` +
      `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`;
    const res = await this.fetchFn(url, {
      headers: { Authorization: `Bearer ${await this.accessToken()}` },
      signal: AbortSignal.timeout(15_000),
    });
    // Jeton inconnu de Google (falsifié, autre application).
    if (res.status === 400 || res.status === 404 || res.status === 410) return null;
    if (!res.ok) throw new Error(`Google Play ${res.status}: ${await res.text()}`);
    return await res.json() as PlayProductPurchase;
  }
}

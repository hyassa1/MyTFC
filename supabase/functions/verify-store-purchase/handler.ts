// verify-store-purchase : débloque un achat fait avec Google Play Billing.
//
// Appelée par l'application (variante store) après chaque achat, et au
// démarrage pour les achats restés non consommés. Idempotente : le même jeton
// d'achat ne crée jamais deux droits (unicité provider + provider_reference).
// L'application ne « consomme » l'achat chez Google qu'après la réponse ok.

import { bearerToken, handle, HttpError, json, readJson } from '../_shared/http.ts';
import type { PlayApi } from '../_shared/stores/google_play.ts';

export interface VerifyStoreBody {
  platform: 'android';
  play_product_id: string;
  purchase_token: string;
}

export interface StoreProduct {
  id: string;
  /** doc_template ou questionnaire quand l'achat porte sur un modèle précis. */
  feature: string;
  requires_resource: boolean;
  /** Prix de référence enregistré dans l'historique (Google ne le renvoie pas). */
  currency: 'USD' | 'CDF';
  amount_minor: number;
}

export interface VerifyStoreDeps {
  play: PlayApi;
  userFromToken(jwt: string): Promise<{ id: string }>;
  productByPlayId(playProductId: string): Promise<StoreProduct | null>;
  resourceExists(feature: string, resourceId: string): Promise<boolean>;
  grant(input: {
    userId: string;
    productId: string;
    resourceId: string | null;
    reference: string;
    currency: string;
    amountMinor: number;
  }): Promise<unknown>;
  /** Accepter les achats de test (testeurs de licence) : jamais en production par défaut. */
  acceptTestPurchases: boolean;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createVerifyStorePurchaseHandler(deps: VerifyStoreDeps) {
  return handle(async (req) => {
    const user = await deps.userFromToken(bearerToken(req));
    const body = await readJson<Partial<VerifyStoreBody>>(req);
    if (body.platform !== 'android') throw new HttpError(400, 'unsupported_platform');
    if (!body.play_product_id || !body.purchase_token || body.purchase_token.length > 1000) {
      throw new HttpError(400, 'invalid_purchase');
    }

    const product = await deps.productByPlayId(body.play_product_id);
    if (!product) throw new HttpError(404, 'product_not_found');

    const purchase = await deps.play.getProductPurchase(body.play_product_id, body.purchase_token);
    if (!purchase) throw new HttpError(400, 'invalid_purchase');
    // En attente (paiement en espèces chez un revendeur, par ex.) : l'app réessaiera.
    if (purchase.purchaseState === 2) return json({ status: 'pending' }, 202);
    if (purchase.purchaseState !== 0) throw new HttpError(400, 'purchase_cancelled');
    if (purchase.purchaseType === 0 && !deps.acceptTestPurchases) {
      throw new HttpError(400, 'test_purchase_rejected');
    }
    // L'achat doit avoir été lancé depuis CE compte (applicationUserName = id utilisateur).
    if (purchase.obfuscatedExternalAccountId !== user.id) {
      throw new HttpError(403, 'purchase_owned_by_other_user');
    }

    // Achat d'un modèle précis : l'identifiant du modèle voyage dans obfuscatedExternalProfileId.
    let resourceId: string | null = null;
    if (product.requires_resource) {
      resourceId = purchase.obfuscatedExternalProfileId ?? null;
      if (
        !resourceId || !UUID.test(resourceId) || !(await deps.resourceExists(product.feature, resourceId))
      ) {
        throw new HttpError(400, 'invalid_resource');
      }
    }

    const result = await deps.grant({
      userId: user.id,
      productId: product.id,
      resourceId,
      reference: body.purchase_token,
      currency: product.currency,
      amountMinor: product.amount_minor,
    });
    return json({ status: 'succeeded', result });
  });
}

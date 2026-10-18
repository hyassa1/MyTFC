// Point d'entrée de l'Edge Function verify-store-purchase (voir handler.ts).

import { HttpError } from '../_shared/http.ts';
import { GooglePlayApi } from '../_shared/stores/google_play.ts';
import { adminClient, userFromToken } from '../_shared/supabase.ts';
import { createVerifyStorePurchaseHandler } from './handler.ts';

const admin = adminClient();
const isProduction = Deno.env.get('MONTFC_ENV') === 'production';

Deno.serve(createVerifyStorePurchaseHandler({
  play: GooglePlayApi.fromEnv(),
  userFromToken: (jwt) => userFromToken(admin, jwt),
  acceptTestPurchases: Deno.env.get('GOOGLE_PLAY_ACCEPT_TEST_PURCHASES') === 'true' || !isProduction,

  async productByPlayId(playProductId) {
    const { data, error } = await admin
      .from('products')
      .select('id, feature, requires_resource, is_active, product_prices(currency, amount_minor)')
      .eq('play_product_id', playProductId)
      .maybeSingle();
    if (error) throw error;
    if (!data || !data.is_active) return null;
    const prices = (data.product_prices ?? []) as { currency: 'USD' | 'CDF'; amount_minor: number }[];
    const price = prices.find((p) => p.currency === 'USD') ?? prices[0];
    if (!price) return null;
    return { id: data.id, feature: data.feature, requires_resource: data.requires_resource, ...price };
  },

  async resourceExists(feature, resourceId) {
    const table = feature === 'questionnaire' ? 'questionnaire_templates' : 'document_templates';
    const { data, error } = await admin.from(table).select('id').eq('id', resourceId).eq('is_published', true)
      .maybeSingle();
    if (error) throw error;
    return Boolean(data);
  },

  async grant(input) {
    const { data, error } = await admin.rpc('grant_store_purchase', {
      p_user_id: input.userId,
      p_product_id: input.productId,
      p_resource_id: input.resourceId,
      p_provider: 'google',
      p_provider_reference: input.reference,
      p_currency: input.currency,
      p_amount_minor: input.amountMinor,
    });
    if (error) {
      if (error.message.includes('store_purchase_owned_by_other_user')) {
        throw new HttpError(403, 'purchase_owned_by_other_user');
      }
      throw error;
    }
    return data;
  },
}));

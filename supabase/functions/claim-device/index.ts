// Point d'entrée de l'Edge Function claim-device (voir handler.ts).

import { adminClient, userFromToken } from '../_shared/supabase.ts';
import { createClaimDeviceHandler } from './handler.ts';

const admin = adminClient();

Deno.serve(createClaimDeviceHandler({
  userFromToken: (jwt) => userFromToken(admin, jwt),

  async claimDevice(userId, body) {
    const { data, error } = await admin.rpc('claim_device', {
      p_user_id: userId,
      p_device_id: body.device_id,
      p_platform: body.platform,
      p_model: body.model ?? null,
      p_app_version: body.app_version ?? null,
      p_app_flavor: body.app_flavor ?? null,
    });
    if (error) throw error;
    return data;
  },

  async signOutOtherSessions(jwt) {
    const { error } = await admin.auth.admin.signOut(jwt, 'others');
    if (error) throw error;
  },
}));

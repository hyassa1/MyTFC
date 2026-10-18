// claim-device : « un compte = un appareil actif ».
//
// Appelée par l'application juste après la connexion OTP :
//   1. enregistre l'appareil et le marque actif (fonction SQL claim_device) ;
//   2. ferme toutes les AUTRES sessions du compte (auth.admin.signOut 'others').
// L'ancien téléphone perd son jeton de rafraîchissement immédiatement et son
// jeton d'accès à expiration (durée courte, voir README). L'app vérifie aussi
// is_active_device() à chaque reprise et se déconnecte proprement.

import { bearerToken, handle, HttpError, json, readJson } from '../_shared/http.ts';

export interface ClaimDeviceBody {
  device_id: string;
  platform: 'android' | 'ios' | 'web';
  model?: string;
  app_version?: string;
  app_flavor?: 'store' | 'direct' | 'web';
}

/** Dépendances injectées (vraies en production, simulées dans les tests). */
export interface ClaimDeviceDeps {
  userFromToken(jwt: string): Promise<{ id: string }>;
  claimDevice(userId: string, body: ClaimDeviceBody): Promise<{
    device_id: string;
    previous_device_id: string | null;
    other_devices_revoked: boolean;
  }>;
  signOutOtherSessions(jwt: string): Promise<void>;
}

const DEVICE_ID = /^[A-Za-z0-9._:-]{8,128}$/;

export function validate(body: Partial<ClaimDeviceBody>): ClaimDeviceBody {
  if (!body.device_id || !DEVICE_ID.test(body.device_id)) throw new HttpError(400, 'invalid_device_id');
  if (!body.platform || !['android', 'ios', 'web'].includes(body.platform)) {
    throw new HttpError(400, 'invalid_platform');
  }
  if (body.app_flavor && !['store', 'direct', 'web'].includes(body.app_flavor)) {
    throw new HttpError(400, 'invalid_flavor');
  }
  return {
    device_id: body.device_id,
    platform: body.platform,
    model: body.model?.slice(0, 120),
    app_version: body.app_version?.slice(0, 30),
    app_flavor: body.app_flavor,
  };
}

export function createClaimDeviceHandler(deps: ClaimDeviceDeps) {
  return handle(async (req) => {
    const jwt = bearerToken(req);
    const user = await deps.userFromToken(jwt);
    const body = validate(await readJson<Partial<ClaimDeviceBody>>(req));

    const result = await deps.claimDevice(user.id, body);
    // Toujours fermer les autres sessions : même appareil mais session
    // résiduelle (réinstallation, connexion sur le web).
    await deps.signOutOtherSessions(jwt);

    return json({ ok: true, ...result });
  });
}

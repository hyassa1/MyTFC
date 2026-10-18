import { assertEquals } from '@std/assert';
import { type ClaimDeviceBody, type ClaimDeviceDeps, createClaimDeviceHandler } from './handler.ts';

function fakeDeps(): ClaimDeviceDeps & { calls: string[]; active: Map<string, string> } {
  const calls: string[] = [];
  const active = new Map<string, string>();
  return {
    calls,
    active,
    userFromToken(jwt) {
      if (jwt !== 'jeton-valide') return Promise.reject(Object.assign(new Error(), { status: 401 }));
      return Promise.resolve({ id: 'user-1' });
    },
    claimDevice(userId: string, body: ClaimDeviceBody) {
      const previous = active.get(userId) ?? null;
      active.set(userId, body.device_id);
      calls.push(`claim:${body.device_id}`);
      return Promise.resolve({
        device_id: body.device_id,
        previous_device_id: previous,
        other_devices_revoked: previous !== body.device_id,
      });
    },
    signOutOtherSessions() {
      calls.push('signout-others');
      return Promise.resolve();
    },
  };
}

function request(body: unknown, token = 'jeton-valide'): Request {
  return new Request('http://localhost/claim-device', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

Deno.test('nouvel appareil : enregistré, puis les autres sessions sont fermées', async () => {
  const deps = fakeDeps();
  const handler = createClaimDeviceHandler(deps);

  const first = await handler(request({ device_id: 'telephone-0001', platform: 'android', app_flavor: 'direct' }));
  assertEquals(first.status, 200);

  const second = await handler(request({ device_id: 'telephone-0002', platform: 'android' }));
  const body = await second.json();
  assertEquals(body.previous_device_id, 'telephone-0001');
  assertEquals(body.other_devices_revoked, true);
  assertEquals(deps.calls, ['claim:telephone-0001', 'signout-others', 'claim:telephone-0002', 'signout-others']);
});

Deno.test('sans jeton : 401', async () => {
  const handler = createClaimDeviceHandler(fakeDeps());
  const res = await handler(new Request('http://localhost', { method: 'POST', body: '{}' }));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, 'not_authenticated');
});

Deno.test('identifiant d\'appareil invalide : 400, rien n\'est modifié', async () => {
  const deps = fakeDeps();
  const handler = createClaimDeviceHandler(deps);
  const res = await handler(request({ device_id: 'x', platform: 'android' }));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, 'invalid_device_id');
  assertEquals(deps.calls, []);
});

Deno.test('plateforme inconnue : 400', async () => {
  const res = await createClaimDeviceHandler(fakeDeps())(request({ device_id: 'telephone-0001', platform: 'symbian' }));
  assertEquals(res.status, 400);
});

Deno.test('méthode GET refusée, OPTIONS accepté (CORS)', async () => {
  const handler = createClaimDeviceHandler(fakeDeps());
  assertEquals((await handler(new Request('http://localhost', { method: 'GET' }))).status, 405);
  assertEquals((await handler(new Request('http://localhost', { method: 'OPTIONS' }))).status, 200);
});

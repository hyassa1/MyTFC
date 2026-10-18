// Client Supabase « service_role » pour les Edge Functions.
//
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement par
// Supabase aux Edge Functions : ils ne doivent JAMAIS être mis dans l'app.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { HttpError } from './http.ts';

let cached: SupabaseClient | undefined;

export function adminClient(): SupabaseClient {
  if (cached) return cached;
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquant');
  cached = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return cached;
}

/** Identifie l'utilisateur à partir de son jeton (vérifié par Supabase Auth). */
export async function userFromToken(admin: SupabaseClient, jwt: string): Promise<{ id: string }> {
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, 'not_authenticated');
  return { id: data.user.id };
}

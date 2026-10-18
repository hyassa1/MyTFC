import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

export const isConfigured = Boolean(url && key);

/** Client Supabase public : tout accès est filtré par les règles RLS. */
export const supabase = createClient(url ?? 'http://localhost:54321', key ?? 'cle-absente', {
  auth: { persistSession: true, autoRefreshToken: true },
});

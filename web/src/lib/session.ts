import type { Session } from '@supabase/supabase-js';
import { useEffect, useState } from 'react';
import { supabase } from './supabase';

/** Session Supabase courante (undefined = en cours de lecture). */
export function useSession(): Session | null | undefined {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);
  return session;
}

/** Rôle admin de l'utilisateur (null = pas admin), lu dans app_admins (RLS : sa propre ligne). */
export function useAdminRole(userId: string | undefined): string | null | undefined {
  const [role, setRole] = useState<string | null | undefined>(undefined);
  useEffect(() => {
    if (!userId) return setRole(undefined);
    supabase
      .from('app_admins')
      .select('role')
      .eq('user_id', userId)
      .maybeSingle()
      .then(({ data }) => setRole(data?.role ?? null));
  }, [userId]);
  return role;
}

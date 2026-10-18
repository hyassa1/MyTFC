import { useEffect, useState } from 'react';
import { parseJsonField } from '../lib/json';
import { supabase } from '../lib/supabase';
import { dbErrorMessage } from './forms';

type Setting = { key: string; value: unknown; is_public: boolean; updated_at: string };

/** Réglages lus par l'application (canaux de paiement, opérateurs…), modifiables sans republier. */
export function SettingsPage() {
  const [settings, setSettings] = useState<Setting[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [messages, setMessages] = useState<Record<string, string>>({});

  async function load() {
    const { data } = await supabase.from('app_settings').select('*').order('key');
    const rows = (data ?? []) as Setting[];
    setSettings(rows);
    setDrafts(Object.fromEntries(rows.map((s) => [s.key, JSON.stringify(s.value, null, 2)])));
  }

  useEffect(() => {
    load();
  }, []);

  async function save(key: string) {
    const parsed = parseJsonField(drafts[key], Array.isArray(settings.find((s) => s.key === key)?.value) ? 'array' : 'object');
    if (!parsed.ok) return setMessages({ ...messages, [key]: parsed.error });
    const { error } = await supabase.from('app_settings').update({ value: parsed.value }).eq('key', key);
    setMessages({ ...messages, [key]: error ? dbErrorMessage(error) : 'Enregistré. Les téléphones le recevront à la prochaine synchronisation.' });
    if (!error) load();
  }

  return (
    <>
      <h1>Réglages</h1>
      <p className="muted">
        Attention : <code>payment_channels</code> décide des moyens de paiement affichés. Sur la version Play Store, ne
        propose que <code>google_play</code> tant que Google n'autorise pas d'autre moyen de paiement en RDC.
      </p>
      {settings.map((s) => (
        <div className="card" key={s.key}>
          <h3><code>{s.key}</code>{s.is_public ? '' : ' (non lu par l\'application)'}</h3>
          <textarea value={drafts[s.key] ?? ''} onChange={(e) => setDrafts({ ...drafts, [s.key]: e.target.value })} />
          <p className="row">
            <button className="primary" onClick={() => save(s.key)}>Enregistrer</button>
            {messages[s.key] && <span>{messages[s.key]}</span>}
          </p>
        </div>
      ))}
    </>
  );
}

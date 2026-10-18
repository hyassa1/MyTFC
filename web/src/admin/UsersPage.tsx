import { useState } from 'react';
import { formatMoney } from '../lib/money';
import { parsePhone } from '../lib/phone';
import { supabase } from '../lib/supabase';
import { useOptions } from './Crud';
import { dbErrorMessage } from './forms';

type Profile = { id: string; phone: string | null; full_name: string | null; faculty: string | null; level: string | null; created_at: string };
type Entitlement = { id: string; product_id: string; feature: string; resource_id: string | null; starts_at: string; expires_at: string | null; source: string; revoked_at: string | null };
type Payment = { id: string; product_id: string; channel: string; status: string; currency: string; amount_net_minor: number; created_at: string; provider_reference: string | null; failure_reason: string | null };

const dt = (v: string | null) => (v ? new Date(v).toLocaleString('fr-FR') : '—');

/** Recherche d'un étudiant par numéro : droits, paiements, et ajout manuel d'un droit (geste commercial, litige). */
export function UsersPage() {
  const options = useOptions();
  const productName = (id: string) => options.products?.find((p) => p.value === id)?.label ?? id;
  const [query, setQuery] = useState('');
  const [profile, setProfile] = useState<Profile | null>(null);
  const [rights, setRights] = useState<Entitlement[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [grant, setGrant] = useState({ product: '', resource: '', reason: '' });

  async function search() {
    setMessage(null);
    const parsed = parsePhone(query);
    if (!parsed) return setMessage('Numéro invalide. Exemple : 0812345678.');
    // Le numéro est stocké sans « + » par Supabase Auth (ex. 243812345678).
    const { data, error } = await supabase
      .from('profiles')
      .select('id, phone, full_name, faculty, level, created_at')
      .in('phone', [parsed.e164, parsed.e164.replace('+', '')])
      .maybeSingle();
    if (error) return setMessage(dbErrorMessage(error));
    setProfile(data);
    if (!data) return setMessage('Aucun compte avec ce numéro.');
    loadDetails(data.id);
  }

  async function loadDetails(userId: string) {
    const [e, p] = await Promise.all([
      supabase.from('entitlements').select('*').eq('user_id', userId).order('created_at', { ascending: false }),
      supabase.from('payments').select('*').eq('user_id', userId).order('created_at', { ascending: false }).limit(50),
    ]);
    setRights((e.data ?? []) as Entitlement[]);
    setPayments((p.data ?? []) as Payment[]);
  }

  async function addRight() {
    if (!profile || !grant.product) return;
    if (grant.resource && !/^[0-9a-f-]{36}$/i.test(grant.resource.trim())) return setMessage('Identifiant de modèle invalide.');
    if (!grant.reason.trim()) return setMessage('Indique la raison (elle reste dans l\'historique).');
    const { error } = await supabase.rpc('admin_grant_entitlement', {
      p_user_id: profile.id,
      p_product_id: grant.product,
      p_resource_id: grant.resource.trim() || null,
      p_reason: grant.reason.trim(),
    });
    if (error) return setMessage(dbErrorMessage(error));
    setGrant({ product: '', resource: '', reason: '' });
    setMessage('Droit ajouté. L\'étudiant le recevra à sa prochaine synchronisation.');
    loadDetails(profile.id);
  }

  return (
    <>
      <h1>Étudiants</h1>
      <div className="card">
        <label htmlFor="q">Numéro de téléphone</label>
        <div className="row">
          <input id="q" style={{ maxWidth: 260 }} inputMode="tel" value={query} onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && search()} />
          <button className="primary" onClick={search}>Rechercher</button>
        </div>
        {message && <p>{message}</p>}
      </div>
      {profile && (
        <>
          <div className="card">
            <h3>{profile.full_name ?? 'Nom non renseigné'}</h3>
            <p className="muted">
              {profile.phone} · {profile.faculty ?? 'Faculté non renseignée'} · {profile.level ?? '—'} · inscrit le {dt(profile.created_at)}
            </p>
          </div>
          <div className="card">
            <h3>Droits d'accès</h3>
            {rights.length === 0 ? <p className="muted">Aucun droit.</p> : (
              <table>
                <thead><tr><th>Offre</th><th>Modèle</th><th>Début</th><th>Fin</th><th>Origine</th></tr></thead>
                <tbody>
                  {rights.map((r) => (
                    <tr key={r.id} className={r.revoked_at ? 'muted' : undefined}>
                      <td>{productName(r.product_id)}{r.revoked_at ? ' (retiré)' : ''}</td>
                      <td>{r.resource_id ? <code>{r.resource_id.slice(0, 8)}</code> : '—'}</td>
                      <td>{dt(r.starts_at)}</td>
                      <td>{r.expires_at ? dt(r.expires_at) : 'Permanent'}</td>
                      <td>{{ payment: 'Paiement', store: 'Google Play', admin_grant: 'Ajout manuel' }[r.source] ?? r.source}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <h4>Ajouter un droit</h4>
            <label htmlFor="g-p">Offre</label>
            <select id="g-p" value={grant.product} onChange={(e) => setGrant({ ...grant, product: e.target.value })}>
              <option value="">— Choisir —</option>
              {(options.products ?? []).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
            <label htmlFor="g-r">Identifiant du modèle (pour un achat à l'unité)</label>
            <input id="g-r" value={grant.resource} onChange={(e) => setGrant({ ...grant, resource: e.target.value })} />
            <label htmlFor="g-why">Raison</label>
            <input id="g-why" placeholder="Ex. paiement débité mais non confirmé, réf. 123" value={grant.reason} onChange={(e) => setGrant({ ...grant, reason: e.target.value })} />
            <p><button className="primary" disabled={!grant.product} onClick={addRight}>Ajouter le droit</button></p>
          </div>
          <div className="card">
            <h3>Paiements</h3>
            {payments.length === 0 ? <p className="muted">Aucun paiement.</p> : (
              <table>
                <thead><tr><th>Date</th><th>Offre</th><th>Canal</th><th>Montant</th><th>État</th><th>Référence</th></tr></thead>
                <tbody>
                  {payments.map((p) => (
                    <tr key={p.id}>
                      <td>{dt(p.created_at)}</td>
                      <td>{productName(p.product_id)}</td>
                      <td>{p.channel}</td>
                      <td>{formatMoney(p.amount_net_minor, p.currency)}</td>
                      <td>{p.status}{p.failure_reason ? ` (${p.failure_reason})` : ''}</td>
                      <td>{p.provider_reference ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}
    </>
  );
}

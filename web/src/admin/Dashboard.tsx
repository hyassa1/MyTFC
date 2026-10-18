import { useCallback, useEffect, useState } from 'react';
import { formatMoney } from '../lib/money';
import { supabase } from '../lib/supabase';
import { dbErrorMessage, fillDays } from './forms';

type Summary = {
  users_total: number;
  users_last_7_days: number;
  payments_today: number;
  revenue_last_30_days: Record<string, number>;
  commissions_due: Record<string, number>;
  active_packs: number;
};
type SalesRow = { day: string; currency: string; purchases: number; revenue_minor: number };
type InstitutionRow = { institution_code: string | null; institution_name: string | null; currency: string; purchases: number; revenue_minor: number };
type CommissionRow = { ambassador_id: string; full_name: string; payout_msisdn: string | null; currency: 'CDF' | 'USD'; sales: number; amount_minor: number };

const DAYS = 30;
const iso = (d: Date) => d.toISOString().slice(0, 10);
const money = (m: Record<string, number> | undefined) =>
  Object.entries(m ?? {}).map(([c, v]) => formatMoney(v, c)).join(' + ') || '0';

/** Tableau de bord : inscriptions, ventes par jour, revenus par université, commissions dues. */
export function Dashboard() {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [signups, setSignups] = useState<{ day: string; value: number }[]>([]);
  const [sales, setSales] = useState<SalesRow[]>([]);
  const [byInstitution, setByInstitution] = useState<InstitutionRow[]>([]);
  const [commissions, setCommissions] = useState<CommissionRow[]>([]);
  const [error, setError] = useState<string | null>(null);

  const from = new Date(Date.now() - (DAYS - 1) * 86400000);

  const load = useCallback(async () => {
    const range = { p_from: iso(from), p_to: iso(new Date()) };
    const [s, su, sa, inst, com] = await Promise.all([
      supabase.rpc('admin_dashboard_summary'),
      supabase.rpc('admin_signups_daily', range),
      supabase.rpc('admin_sales_daily', range),
      supabase.rpc('admin_revenue_by_institution', range),
      supabase.rpc('admin_commissions_due'),
    ]);
    const failed = [s, su, sa, inst, com].find((r) => r.error);
    if (failed) setError(dbErrorMessage(failed.error));
    setSummary(s.data as Summary);
    setSignups(fillDays((su.data ?? []) as { day: string; signups: number }[], from, DAYS, (r) => Number(r.signups)));
    setSales((sa.data ?? []) as SalesRow[]);
    setByInstitution((inst.data ?? []) as InstitutionRow[]);
    setCommissions((com.data ?? []) as CommissionRow[]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function markPaid(c: CommissionRow) {
    const reference = window.prompt(
      `Commission de ${c.full_name} : ${formatMoney(c.amount_minor, c.currency)}.\nRéférence du transfert mobile money :`,
    );
    if (!reference?.trim()) return;
    const { error } = await supabase.rpc('admin_mark_commissions_paid', {
      p_ambassador_id: c.ambassador_id,
      p_currency: c.currency,
      p_reference: reference.trim(),
    });
    if (error) return setError(dbErrorMessage(error));
    load();
  }

  const purchasesPerDay = fillDays(sales, from, DAYS, (r) => Number(r.purchases));

  return (
    <>
      <h1>Tableau de bord</h1>
      {error && <p className="error">{error}</p>}
      <div className="grid" style={{ marginBottom: 16 }}>
        <Stat label="Inscrits" value={summary?.users_total ?? '…'} />
        <Stat label="Inscrits (7 derniers jours)" value={summary?.users_last_7_days ?? '…'} />
        <Stat label="Paiements aujourd'hui" value={summary?.payments_today ?? '…'} />
        <Stat label="Packs actifs" value={summary?.active_packs ?? '…'} />
        <Stat label="Revenus (30 jours)" value={summary ? money(summary.revenue_last_30_days) : '…'} />
        <Stat label="Commissions dues" value={summary ? money(summary.commissions_due) : '…'} />
      </div>
      <div className="card">
        <h3>Inscriptions par jour (30 jours)</h3>
        <Bars data={signups} unit="inscription" />
      </div>
      <div className="card">
        <h3>Achats par jour (30 jours)</h3>
        <Bars data={purchasesPerDay} unit="achat" />
        <SalesTable rows={sales} />
      </div>
      <div className="card">
        <h3>Revenus par université (30 jours)</h3>
        {byInstitution.length === 0 ? (
          <p className="muted">Aucune vente sur la période.</p>
        ) : (
          <table>
            <thead><tr><th>Établissement</th><th>Devise</th><th>Achats</th><th>Revenus</th></tr></thead>
            <tbody>
              {byInstitution.map((r, i) => (
                <tr key={i}>
                  <td>{r.institution_name ?? 'Non renseigné'}</td>
                  <td>{r.currency}</td>
                  <td>{r.purchases}</td>
                  <td>{formatMoney(r.revenue_minor, r.currency)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      <div className="card">
        <h3>Commissions dues aux ambassadeurs</h3>
        {commissions.length === 0 ? (
          <p className="muted">Aucune commission à payer.</p>
        ) : (
          <table>
            <thead><tr><th>Ambassadeur</th><th>Numéro de paiement</th><th>Ventes</th><th>Montant</th><th /></tr></thead>
            <tbody>
              {commissions.map((c) => (
                <tr key={`${c.ambassador_id}-${c.currency}`}>
                  <td>{c.full_name}</td>
                  <td>{c.payout_msisdn ?? <span className="error">À renseigner</span>}</td>
                  <td>{c.sales}</td>
                  <td>{formatMoney(c.amount_minor, c.currency)}</td>
                  <td><button onClick={() => markPaid(c)}>Marquer payé</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="card stat" style={{ marginBottom: 0 }}>
      <div className="label">{label}</div>
      <div className="value">{value}</div>
    </div>
  );
}

/** Histogramme simple en CSS (pas de bibliothèque de graphiques : page plus légère). */
function Bars({ data, unit }: { data: { day: string; value: number }[]; unit: string }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  const total = data.reduce((s, d) => s + d.value, 0);
  return (
    <>
      <div className="bars" role="img" aria-label={`${total} ${unit}(s) sur la période`}>
        {data.map((d) => (
          <div key={d.day} style={{ height: `${(d.value / max) * 100}%` }} title={`${new Date(d.day).toLocaleDateString('fr-FR')} : ${d.value}`} />
        ))}
      </div>
      <p className="muted">Total : {total} · maximum sur un jour : {max === 1 && total === 0 ? 0 : max}</p>
    </>
  );
}

function SalesTable({ rows }: { rows: SalesRow[] }) {
  if (rows.length === 0) return <p className="muted">Aucune vente sur la période.</p>;
  const sorted = [...rows].sort((a, b) => b.day.localeCompare(a.day));
  return (
    <details>
      <summary>Détail par jour</summary>
      <table>
        <thead><tr><th>Jour</th><th>Devise</th><th>Achats</th><th>Revenus</th></tr></thead>
        <tbody>
          {sorted.map((r) => (
            <tr key={`${r.day}-${r.currency}`}>
              <td>{new Date(r.day).toLocaleDateString('fr-FR')}</td>
              <td>{r.currency}</td>
              <td>{r.purchases}</td>
              <td>{formatMoney(r.revenue_minor, r.currency)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </details>
  );
}

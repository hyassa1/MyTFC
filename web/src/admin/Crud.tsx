import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { minorToInput } from '../lib/money';
import { supabase } from '../lib/supabase';
import { dbErrorMessage, parseForm, toFormValue, type Field, type FormValues, type Option } from './forms';

/** Listes de choix partagées (institutions, offres, ambassadeurs), chargées une fois par page. */
export function useOptions(): Record<string, Option[]> {
  const [lists, setLists] = useState<Record<string, Option[]>>({});
  useEffect(() => {
    Promise.all([
      supabase.from('institutions').select('id, name').order('position'),
      supabase.from('products').select('id, name').order('position'),
      supabase.from('ambassadors').select('id, full_name').order('full_name'),
    ]).then(([inst, prod, amb]) =>
      setLists({
        institutions: (inst.data ?? []).map((r) => ({ value: r.id, label: r.name })),
        products: (prod.data ?? []).map((r) => ({ value: r.id, label: r.name })),
        ambassadors: (amb.data ?? []).map((r) => ({ value: r.id, label: r.full_name })),
      }),
    );
  }, []);
  return lists;
}

export type CrudConfig = {
  title: string;
  table: string;
  /** Table des contenus payants (clé template_id), pour les champs json inBody. */
  bodyTable?: string;
  /** Prix stockés dans product_prices. */
  withPrices?: boolean;
  order: string;
  desc?: boolean;
  /** Suppression douce (deleted_at) : la ligne disparaît des téléphones à la synchro suivante. */
  softDelete?: boolean;
  fields: Field[];
  columns: { label: string; render: (row: Row) => ReactNode }[];
  /** Valeurs d'une nouvelle fiche. */
  defaults?: Record<string, unknown>;
  intro?: ReactNode;
};

export type Row = Record<string, unknown> & { id: string };

/** Page générique : liste + formulaire de création / modification. */
export function CrudPage({ config }: { config: CrudConfig }) {
  const options = useOptions();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Row | 'new' | null>(null);

  const load = useCallback(async () => {
    let query = supabase.from(config.table).select(config.withPrices ? '*, product_prices(currency, amount_minor)' : '*');
    if (config.softDelete) query = query.is('deleted_at', null);
    const { data, error } = await query.order(config.order, { ascending: !config.desc });
    if (error) setLoadError(dbErrorMessage(error));
    setRows((data as unknown as Row[]) ?? []);
  }, [config]);

  useEffect(() => {
    setEditing(null);
    setRows(null);
    load();
  }, [load]);

  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <h1>{config.title}</h1>
        {!editing && <button className="primary" onClick={() => setEditing('new')}>Ajouter</button>}
      </div>
      {config.intro && !editing && <div className="muted">{config.intro}</div>}
      {loadError && <p className="error">{loadError}</p>}
      {editing ? (
        <RecordForm
          config={config}
          options={options}
          row={editing === 'new' ? null : editing}
          onDone={(changed) => {
            setEditing(null);
            if (changed) load();
          }}
        />
      ) : rows === null ? (
        <p className="muted">Chargement…</p>
      ) : rows.length === 0 ? (
        <p className="muted">Rien pour le moment.</p>
      ) : (
        <div className="card">
          <table>
            <thead>
              <tr>
                {config.columns.map((c) => <th key={c.label}>{c.label}</th>)}
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  {config.columns.map((c) => <td key={c.label}>{c.render(r)}</td>)}
                  <td><button onClick={() => setEditing(r)}>Modifier</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function RecordForm({ config, options, row, onDone }: {
  config: CrudConfig;
  options: Record<string, Option[]>;
  row: Row | null;
  onDone: (changed: boolean) => void;
}) {
  const [values, setValues] = useState<FormValues | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Valeurs initiales : la ligne, son contenu payant et ses prix.
  useEffect(() => {
    (async () => {
      const source: Record<string, unknown> = { ...(config.defaults ?? {}), ...(row ?? {}) };
      if (row && config.bodyTable) {
        const { data } = await supabase.from(config.bodyTable).select('*').eq('template_id', row.id).maybeSingle();
        Object.assign(source, data ?? {});
      }
      const prices = (row?.product_prices as { currency: string; amount_minor: number }[] | undefined) ?? [];
      const initial: FormValues = {};
      for (const f of config.fields) {
        if (f.type === 'money') {
          const p = prices.find((x) => x.currency === f.currency);
          initial[f.key] = p ? minorToInput(p.amount_minor, p.currency) : '';
        } else {
          initial[f.key] = toFormValue(f, source[f.key]);
        }
      }
      setValues(initial);
    })();
  }, [config, row]);

  if (!values) return <p className="muted">Chargement…</p>;

  const set = (key: string, v: string | boolean | string[]) => setValues({ ...values, [key]: v });

  async function save() {
    const parsed = parseForm(config.fields, values!);
    setErrors(parsed.errors);
    if (Object.keys(parsed.errors).length) return setMessage('Corrige les champs signalés.');
    setBusy(true);
    setMessage(null);
    try {
      const { data, error } = row
        ? await supabase.from(config.table).update(parsed.row).eq('id', row.id).select('id').single()
        : await supabase.from(config.table).insert(parsed.row).select('id').single();
      if (error) throw error;
      const id = (data as { id: string }).id;
      if (config.bodyTable && Object.keys(parsed.body).length) {
        const { error: e } = await supabase.from(config.bodyTable).upsert({ template_id: id, ...parsed.body });
        if (e) throw e;
      }
      if (config.withPrices) {
        for (const p of parsed.prices) {
          const { error: e } = p.amount_minor === null
            ? await supabase.from('product_prices').delete().eq('product_id', id).eq('currency', p.currency)
            : await supabase.from('product_prices').upsert({ product_id: id, currency: p.currency, amount_minor: p.amount_minor });
          if (e) throw e;
        }
      }
      onDone(true);
    } catch (e) {
      setMessage(dbErrorMessage(e as { code?: string; message?: string }));
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!row || !window.confirm('Retirer cet élément ? Il disparaîtra des téléphones à la prochaine synchronisation.')) return;
    setBusy(true);
    const { error } = await supabase
      .from(config.table)
      .update({ deleted_at: new Date().toISOString(), is_published: false })
      .eq('id', row.id);
    setBusy(false);
    if (error) return setMessage(dbErrorMessage(error));
    onDone(true);
  }

  return (
    <div className="card">
      <h2>{row ? 'Modifier' : 'Ajouter'}</h2>
      {config.fields.map((f) => (
        <FieldInput key={f.key} field={f} value={values[f.key]} error={errors[f.key]} options={options} onChange={(v) => set(f.key, v)} />
      ))}
      {message && <p className="error">{message}</p>}
      <p className="row">
        <button className="primary" disabled={busy} onClick={save}>Enregistrer</button>
        <button disabled={busy} onClick={() => onDone(false)}>Annuler</button>
        {row && config.softDelete && <button disabled={busy} onClick={remove} className="error">Retirer</button>}
      </p>
    </div>
  );
}

function FieldInput({ field: f, value, error, options, onChange }: {
  field: Field;
  value: string | boolean | string[];
  error?: string;
  options: Record<string, Option[]>;
  onChange: (v: string | boolean | string[]) => void;
}) {
  const id = `f-${f.key}`;
  const opts = typeof f.options === 'string' ? options[f.options] ?? [] : f.options ?? [];
  let input: ReactNode;
  switch (f.type) {
    case 'checkbox':
      return (
        <p>
          <label className="row" htmlFor={id} style={{ color: 'var(--text)' }}>
            <input id={id} type="checkbox" checked={value === true} onChange={(e) => onChange(e.target.checked)} /> {f.label}
          </label>
          {f.help && <span className="muted">{f.help}</span>}
        </p>
      );
    case 'textarea':
    case 'markdown':
    case 'json':
      input = (
        <textarea
          id={id}
          value={value as string}
          style={f.type === 'textarea' ? { fontFamily: 'inherit', minHeight: 70 } : { minHeight: f.type === 'json' ? 260 : 360 }}
          onChange={(e) => onChange(e.target.value)}
        />
      );
      break;
    case 'select':
      input = (
        <select id={id} value={value as string} onChange={(e) => onChange(e.target.value)}>
          <option value="">{f.required ? '— Choisir —' : '— Aucun —'}</option>
          {opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
      );
      break;
    case 'multiselect': {
      const list = value as string[];
      input = (
        <div className="row">
          {opts.map((o) => (
            <label key={o.value} className="row" style={{ margin: 0, color: 'var(--text)' }}>
              <input
                type="checkbox"
                checked={list.includes(o.value)}
                onChange={(e) => onChange(e.target.checked ? [...list, o.value] : list.filter((x) => x !== o.value))}
              />
              {o.label}
            </label>
          ))}
        </div>
      );
      break;
    }
    case 'datetime':
      input = <input id={id} type="datetime-local" value={value as string} onChange={(e) => onChange(e.target.value)} />;
      break;
    default:
      input = (
        <input
          id={id}
          inputMode={f.type === 'number' || f.type === 'money' ? 'decimal' : undefined}
          value={value as string}
          onChange={(e) => onChange(f.upper ? e.target.value.toUpperCase() : e.target.value)}
        />
      );
  }
  return (
    <div>
      <label htmlFor={id}>{f.label}{f.required ? ' *' : ''}</label>
      {input}
      {f.help && <div className="muted" style={{ fontSize: 13, marginTop: 4 }}>{f.help}</div>}
      {error && <div className="error" style={{ fontSize: 13, marginTop: 4 }}>{error}</div>}
    </div>
  );
}

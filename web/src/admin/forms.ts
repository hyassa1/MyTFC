// Outils purs du panneau d'administration (testés dans admin.test.ts).

import { parseJsonField } from '../lib/json';
import { parseMoney } from '../lib/money';

export type Option = { value: string; label: string };

/** Description d'un champ de formulaire générique. */
export type Field = {
  key: string;
  label: string;
  type: 'text' | 'textarea' | 'markdown' | 'number' | 'checkbox' | 'select' | 'multiselect' | 'datetime' | 'json' | 'money';
  required?: boolean;
  help?: string;
  /** Liste fixe, ou nom d'une liste chargée par la page (institutions, produits…). */
  options?: Option[] | string;
  /** json : forme attendue et vérification supplémentaire. */
  expected?: 'object' | 'array';
  check?: (value: unknown) => string[];
  /** json : colonne stockée dans la table des contenus payants (bodyTable). */
  inBody?: boolean;
  /** money : devise (stockée dans product_prices). */
  currency?: 'CDF' | 'USD';
  /** Champ en majuscules (codes). */
  upper?: boolean;
  /** Expression régulière du serveur, pour prévenir avant l'envoi. */
  pattern?: RegExp;
  patternHelp?: string;
};

export type FormValues = Record<string, string | boolean | string[]>;

/** Valeur de la base → valeur du formulaire. */
export function toFormValue(field: Field, value: unknown): string | boolean | string[] {
  switch (field.type) {
    case 'checkbox':
      return value === true;
    case 'multiselect':
      return Array.isArray(value) ? value.map(String) : [];
    case 'json':
      return value === undefined || value === null ? (field.expected === 'array' ? '[]' : '{}') : JSON.stringify(value, null, 2);
    case 'datetime':
      return typeof value === 'string' && value ? toLocalInput(new Date(value)) : '';
    case 'number':
      return value === null || value === undefined ? '' : String(value);
    default:
      return value === null || value === undefined ? '' : String(value);
  }
}

/** « 2026-10-18T09:30 » (heure locale) attendu par <input type="datetime-local">. */
export function toLocalInput(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

export type ParsedForm = {
  row: Record<string, unknown>;
  body: Record<string, unknown>;
  prices: { currency: 'CDF' | 'USD'; amount_minor: number | null }[];
  errors: Record<string, string>;
};

/** Formulaire → lignes à enregistrer, avec les erreurs champ par champ. */
export function parseForm(fields: Field[], values: FormValues): ParsedForm {
  const out: ParsedForm = { row: {}, body: {}, prices: [], errors: {} };
  for (const f of fields) {
    const raw = values[f.key];
    const text = typeof raw === 'string' ? raw.trim() : '';
    const missing = () => (out.errors[f.key] = 'Champ obligatoire.');
    switch (f.type) {
      case 'checkbox':
        out.row[f.key] = raw === true;
        break;
      case 'multiselect': {
        const list = Array.isArray(raw) ? raw : [];
        if (f.required && list.length === 0) missing();
        out.row[f.key] = list.length ? list : null;
        break;
      }
      case 'number': {
        if (!text) {
          if (f.required) missing();
          out.row[f.key] = null;
        } else if (!/^-?\d+(\.\d+)?$/.test(text.replace(',', '.'))) {
          out.errors[f.key] = 'Nombre attendu.';
        } else {
          out.row[f.key] = Number(text.replace(',', '.'));
        }
        break;
      }
      case 'datetime':
        if (!text && f.required) missing();
        out.row[f.key] = text ? new Date(text).toISOString() : null;
        break;
      case 'json': {
        const parsed = parseJsonField(text || (f.expected === 'array' ? '[]' : '{}'), f.expected ?? 'object');
        if (!parsed.ok) {
          out.errors[f.key] = parsed.error;
          break;
        }
        const problems = f.check?.(parsed.value) ?? [];
        if (problems.length) out.errors[f.key] = problems.join(' ');
        (f.inBody ? out.body : out.row)[f.key] = parsed.value;
        break;
      }
      case 'money': {
        if (!text) {
          if (f.required) missing();
          out.prices.push({ currency: f.currency!, amount_minor: null });
          break;
        }
        const minor = parseMoney(text);
        if (minor === null || minor <= 0) out.errors[f.key] = 'Montant invalide (ex. 5 800 ou 2,50).';
        else out.prices.push({ currency: f.currency!, amount_minor: minor });
        break;
      }
      default: {
        const value = f.upper ? text.toUpperCase() : text;
        if (!value) {
          if (f.required) missing();
          out.row[f.key] = null;
        } else if (f.pattern && !f.pattern.test(value)) {
          out.errors[f.key] = f.patternHelp ?? 'Format invalide.';
        } else {
          out.row[f.key] = value;
        }
      }
    }
  }
  return out;
}

/** Complète une série quotidienne (les jours sans valeur valent 0), du plus ancien au plus récent. */
export function fillDays<T extends { day: string }>(rows: T[], from: Date, days: number, value: (r: T) => number) {
  const byDay = new Map<string, number>();
  for (const r of rows) byDay.set(r.day, (byDay.get(r.day) ?? 0) + value(r));
  return Array.from({ length: days }, (_, i) => {
    const d = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), from.getUTCDate() + i));
    const key = d.toISOString().slice(0, 10);
    return { day: key, value: byDay.get(key) ?? 0 };
  });
}

/** Message lisible pour une erreur PostgREST (contraintes de la base). */
export function dbErrorMessage(error: { code?: string; message?: string } | null | undefined): string {
  if (!error) return '';
  if (error.code === '23505') return 'Cette valeur existe déjà (code ou identifiant en double).';
  if (error.code === '23514') return 'Une valeur ne respecte pas les règles de la base (format, bornes).';
  if (error.code === '23503') return 'Élément lié introuvable ou encore utilisé ailleurs.';
  if (error.code === '42501') return 'Ce compte n\'a pas le droit de faire cette modification.';
  return error.message ?? 'L\'enregistrement a échoué.';
}

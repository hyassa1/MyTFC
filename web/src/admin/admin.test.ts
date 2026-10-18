import { describe, expect, it } from 'vitest';
import { checkCoverLayout } from '../lib/json';
import { dbErrorMessage, fillDays, parseForm, toFormValue, type Field } from './forms';

const fields: Field[] = [
  { key: 'code', label: 'Code', type: 'text', required: true, upper: true, pattern: /^[A-Z0-9_-]{3,32}$/ },
  { key: 'discount_percent', label: 'Réduction', type: 'number', required: true },
  { key: 'max_uses', label: 'Max', type: 'number' },
  { key: 'applies_to', label: 'Offres', type: 'multiselect' },
  { key: 'is_active', label: 'Actif', type: 'checkbox' },
  { key: 'layout', label: 'Mise en page', type: 'json', expected: 'object', inBody: true, check: checkCoverLayout },
  { key: 'cdf', label: 'Prix FC', type: 'money', currency: 'CDF' },
  { key: 'usd', label: 'Prix $', type: 'money', currency: 'USD' },
];

describe('parseForm', () => {
  it('convertit les valeurs pour la base', () => {
    const r = parseForm(fields, {
      code: 'unikin2026', discount_percent: '15', max_uses: '', applies_to: [], is_active: true,
      layout: '{"schema_version":1,"blocks":[{"type":"text","text":"{{titre}}"}]}', cdf: '5 800', usd: '',
    });
    expect(r.errors).toEqual({});
    expect(r.row).toEqual({ code: 'UNIKIN2026', discount_percent: 15, max_uses: null, applies_to: null, is_active: true });
    expect(r.body).toEqual({ layout: { schema_version: 1, blocks: [{ type: 'text', text: '{{titre}}' }] } });
    expect(r.prices).toEqual([{ currency: 'CDF', amount_minor: 580000 }, { currency: 'USD', amount_minor: null }]);
  });

  it('signale les erreurs champ par champ', () => {
    const r = parseForm(fields, {
      code: 'a b', discount_percent: '', max_uses: 'dix', applies_to: [], is_active: false,
      layout: '{"blocks":[{"type":"image"}]}', cdf: '0', usd: '2,505',
    });
    expect(Object.keys(r.errors).sort()).toEqual(['cdf', 'code', 'discount_percent', 'layout', 'max_uses', 'usd']);
    expect(r.errors.layout).toContain('image');
  });

  it('refuse un JSON mal formé', () => {
    const r = parseForm([fields[5]], { layout: '{blocks: []' });
    expect(r.errors.layout).toMatch(/JSON invalide/);
  });
});

describe('toFormValue', () => {
  it('prépare les valeurs pour le formulaire', () => {
    expect(toFormValue({ key: 'x', label: '', type: 'json', expected: 'array' }, null)).toBe('[]');
    expect(toFormValue({ key: 'x', label: '', type: 'number' }, 12)).toBe('12');
    expect(toFormValue({ key: 'x', label: '', type: 'checkbox' }, null)).toBe(false);
    expect(toFormValue({ key: 'x', label: '', type: 'datetime' }, null)).toBe('');
  });
});

describe('fillDays', () => {
  it('complète les jours sans valeur et additionne les devises', () => {
    const rows = [
      { day: '2026-10-02', purchases: 2 },
      { day: '2026-10-02', purchases: 1 },
      { day: '2026-10-04', purchases: 5 },
    ];
    const out = fillDays(rows, new Date('2026-10-01T00:00:00Z'), 4, (r) => r.purchases);
    expect(out).toEqual([
      { day: '2026-10-01', value: 0 },
      { day: '2026-10-02', value: 3 },
      { day: '2026-10-03', value: 0 },
      { day: '2026-10-04', value: 5 },
    ]);
  });
});

describe('dbErrorMessage', () => {
  it('traduit les erreurs fréquentes', () => {
    expect(dbErrorMessage({ code: '23505' })).toMatch(/existe déjà/);
    expect(dbErrorMessage({ code: '42501' })).toMatch(/droit/);
  });
});

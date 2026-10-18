// Montants stockés en unités mineures (×100) pour le CDF comme pour l'USD.

export type Currency = 'CDF' | 'USD';

/** 580000 CDF → « 5 800 FC » ; 250 USD → « 2,50 $ ». */
export function formatMoney(minor: number, currency: Currency | string): string {
  const major = minor / 100;
  if (currency === 'CDF') {
    return `${new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(Math.round(major))} FC`
      .replace(/ | /g, ' ');
  }
  return `${new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(major)} $`
    .replace(/ | /g, ' ');
}

/** Saisie de l'admin (« 5 800 », « 2,50 ») → unités mineures, ou null si invalide. */
export function parseMoney(input: string): number | null {
  const cleaned = input.replace(/[\s  ]/g, '').replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;
  return Math.round(Number(cleaned) * 100);
}

/** Unités mineures → texte modifiable (« 5800 », « 2.5 » devient « 2,50 »). */
export function minorToInput(minor: number, currency: Currency | string): string {
  const major = minor / 100;
  return currency === 'CDF' && Number.isInteger(major) ? String(major) : major.toFixed(2).replace('.', ',');
}

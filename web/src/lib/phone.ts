// Numéros congolais : 0812345678, 812345678, +243812345678, 243 81 234 5678.

const OPERATORS: Record<string, string> = {
  '81': 'vodacom', '82': 'vodacom', '83': 'vodacom',
  '84': 'orange', '85': 'orange', '89': 'orange', '80': 'orange',
  '97': 'airtel', '98': 'airtel', '99': 'airtel',
  '90': 'afrimoney', '91': 'afrimoney',
};

export interface Phone {
  /** Format international : +243812345678 */
  e164: string;
  /** Opérateur mobile money probable (modifiable par l'utilisateur). */
  operator: string | null;
}

export function parsePhone(raw: string): Phone | null {
  let digits = raw.replace(/[\s.\-()]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('243')) digits = digits.slice(3);
  if (digits.startsWith('0')) digits = digits.slice(1);
  if (!/^[89]\d{8}$/.test(digits)) return null;
  return { e164: `+243${digits}`, operator: OPERATORS[digits.slice(0, 2)] ?? null };
}

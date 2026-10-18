import { describe, expect, it } from 'vitest';
import { checkCoverLayout, parseJsonField } from './json';
import { formatMoney, minorToInput, parseMoney } from './money';
import { parsePhone } from './phone';
import { errorMessage } from './errors';

describe('montants', () => {
  it('affiche CDF sans décimales et USD avec deux décimales', () => {
    expect(formatMoney(580000, 'CDF')).toBe('5 800 FC');
    expect(formatMoney(250, 'USD')).toBe('2,50 $');
  });
  it('lit la saisie de l\'admin', () => {
    expect(parseMoney('5 800')).toBe(580000);
    expect(parseMoney('2,5')).toBe(250);
    expect(parseMoney('10.99')).toBe(1099);
    expect(parseMoney('-3')).toBeNull();
    expect(parseMoney('1,234')).toBeNull();
    expect(minorToInput(580000, 'CDF')).toBe('5800');
    expect(minorToInput(250, 'USD')).toBe('2,50');
  });
});

describe('téléphone', () => {
  it('normalise et devine l\'opérateur', () => {
    expect(parsePhone('081 234 5678')).toEqual({ e164: '+243812345678', operator: 'vodacom' });
    expect(parsePhone('+243 99 123 4567')?.operator).toBe('airtel');
    expect(parsePhone('00243841234567')?.e164).toBe('+243841234567');
    expect(parsePhone('0712345678')).toBeNull();
    expect(parsePhone('08123')).toBeNull();
  });
});

describe('JSON des modèles', () => {
  it('refuse un JSON invalide ou du mauvais type', () => {
    expect(parseJsonField('{', 'object').ok).toBe(false);
    expect(parseJsonField('[]', 'object')).toEqual({ ok: false, error: 'Un objet { … } est attendu.' });
    expect(parseJsonField('[1]', 'array').ok).toBe(true);
  });
  it('vérifie une mise en page de page de garde', () => {
    expect(checkCoverLayout({ blocks: [{ type: 'text', text: 'A' }, { type: 'box', blocks: [{ type: 'image' }] }] }))
      .toEqual(['blocks[1].blocks[0] : type inconnu « image ».']);
    expect(checkCoverLayout({ schema_version: 2, blocks: [] })).toHaveLength(1);
  });
});

it('messages d\'erreur en français', () => {
  expect(errorMessage('insufficient_funds')).toContain('Solde insuffisant');
  expect(errorMessage('flexpay_unreachable')).toContain('ne répond pas');
  expect(errorMessage(undefined)).toContain('pas abouti');
});

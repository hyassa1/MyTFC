/** Lecture d'un champ JSON saisi par l'admin, avec un message clair. */
export function parseJsonField(
  text: string,
  expected: 'object' | 'array',
): { ok: true; value: unknown } | { ok: false; error: string } {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (e) {
    return { ok: false, error: `JSON invalide : ${(e as Error).message}` };
  }
  const isArray = Array.isArray(value);
  if (expected === 'array' && !isArray) return { ok: false, error: 'Une liste [ … ] est attendue.' };
  if (expected === 'object' && (isArray || value === null || typeof value !== 'object')) {
    return { ok: false, error: 'Un objet { … } est attendu.' };
  }
  return { ok: true, value };
}

/** Vérifie une mise en page de page de garde (format version 1). */
export function checkCoverLayout(layout: unknown): string[] {
  const errors: string[] = [];
  const l = layout as { schema_version?: number; blocks?: unknown[] };
  if (l.schema_version !== undefined && l.schema_version > 1) errors.push('schema_version > 1 : l\'application ne le lira pas.');
  if (!Array.isArray(l.blocks)) {
    errors.push('« blocks » doit être une liste.');
    return errors;
  }
  const types = new Set(['text', 'spacer', 'rule', 'box']);
  const walk = (blocks: unknown[], path: string) =>
    blocks.forEach((b, i) => {
      const block = b as { type?: string; text?: unknown; blocks?: unknown[] };
      if (!types.has(block.type ?? '')) errors.push(`${path}[${i}] : type inconnu « ${block.type} ».`);
      if (block.type === 'text' && typeof block.text !== 'string') errors.push(`${path}[${i}] : « text » manquant.`);
      if (block.type === 'box') walk(Array.isArray(block.blocks) ? block.blocks : [], `${path}[${i}].blocks`);
    });
  walk(l.blocks, 'blocks');
  return errors;
}

import { describe, expect, it } from 'vitest';
import { buildOffers, GRACE_MS, nextStep } from './payment';

describe('page de paiement', () => {
  it('offres actives, triées, avec leurs prix', () => {
    const offers = buildOffers(
      [
        { id: 'a', code: 'COVER_PAGE', name: 'Page de garde', description: null, feature: 'cover_page', requires_resource: false, is_active: true, position: 2 },
        { id: 'b', code: 'PACK_FINALISTE', name: 'Pack', description: null, feature: 'all', requires_resource: false, is_active: true, position: 0 },
        { id: 'c', code: 'OLD', name: 'Ancienne', description: null, feature: 'export', requires_resource: false, is_active: false, position: 1 },
        { id: 'd', code: 'NOPRICE', name: 'Sans prix', description: null, feature: 'export', requires_resource: false, is_active: true, position: 1 },
      ],
      [
        { product_id: 'a', currency: 'CDF', amount_minor: 580000 },
        { product_id: 'b', currency: 'USD', amount_minor: 1000 },
        { product_id: 'c', currency: 'USD', amount_minor: 100 },
      ],
    );
    expect(offers.map((o) => o.code)).toEqual(['PACK_FINALISTE', 'COVER_PAGE']);
    expect(offers[1].prices).toEqual({ CDF: 580000 });
  });

  it('suivi : succès, échec, attente puis délai dépassé', () => {
    const now = Date.parse('2026-10-18T10:00:00Z');
    const base = { id: 'p', currency: 'CDF', amount_net_minor: 1 };
    expect(nextStep({ ...base, status: 'processing' }, now)).toBe('wait');
    expect(nextStep({ ...base, status: 'succeeded' }, now)).toBe('success');
    expect(nextStep({ ...base, status: 'failed' }, now)).toBe('failure');
    const expired = { ...base, status: 'expired' as const, expires_at: '2026-10-18T09:59:00Z' };
    expect(nextStep(expired, now)).toBe('wait');
    expect(nextStep(expired, now + GRACE_MS)).toBe('timeout');
  });
});

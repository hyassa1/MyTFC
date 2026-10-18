import 'package:flutter_test/flutter_test.dart';
import 'package:montfc/features/store/domain/entitlement.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 12);

  Entitlement ent(AppFeature f, {String? resource, DateTime? starts, DateTime? expires, DateTime? revoked}) =>
      Entitlement(
        id: 'e',
        feature: f,
        resourceId: resource,
        startsAt: starts ?? now.subtract(const Duration(days: 1)),
        expiresAt: expires,
        revokedAt: revoked,
      );

  test('le Pack Finaliste ouvre tout', () {
    final set = EntitlementSet([ent(AppFeature.all, expires: now.add(const Duration(days: 300)))]);
    expect(set.hasAccess(AppFeature.coverPage, now: now), isTrue);
    expect(set.hasAccess(AppFeature.docTemplate, resourceId: 'x', now: now), isTrue);
    expect(set.hasAccess(AppFeature.export, now: now), isTrue);
  });

  test('un achat à l\'unité ne vaut que pour son modèle', () {
    final set = EntitlementSet([ent(AppFeature.docTemplate, resource: 'modele-1')]);
    expect(set.hasAccess(AppFeature.docTemplate, resourceId: 'modele-1', now: now), isTrue);
    expect(set.hasAccess(AppFeature.docTemplate, resourceId: 'modele-2', now: now), isFalse);
    expect(set.hasAccess(AppFeature.coverPage, now: now), isFalse);
  });

  test('un droit expiré, révoqué ou pas encore commencé ne donne rien', () {
    expect(EntitlementSet([ent(AppFeature.all, expires: now.subtract(const Duration(seconds: 1)))])
        .hasAccess(AppFeature.coverPage, now: now), isFalse);
    expect(EntitlementSet([ent(AppFeature.all, revoked: now)]).hasAccess(AppFeature.coverPage, now: now), isFalse);
    expect(EntitlementSet([ent(AppFeature.all, starts: now.add(const Duration(days: 1)))])
        .hasAccess(AppFeature.coverPage, now: now), isFalse);
  });

  test('fin du pack = la plus lointaine des dates actives', () {
    final end1 = now.add(const Duration(days: 10));
    final end2 = now.add(const Duration(days: 375));
    final set = EntitlementSet([ent(AppFeature.all, expires: end1), ent(AppFeature.all, expires: end2)]);
    expect(set.packExpiry(now: now), end2);
  });

  test('aller-retour JSON', () {
    final e = Entitlement.fromJson({
      'id': 'abc',
      'feature': 'cover_page',
      'resource_id': null,
      'starts_at': '2026-10-18T10:00:00+00:00',
      'expires_at': null,
      'revoked_at': null,
    });
    expect(Entitlement.fromJson(e.toJson()).feature, AppFeature.coverPage);
  });
}

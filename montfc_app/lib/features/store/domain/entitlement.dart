/// Fonctions débloquables (miroir de l'enum SQL `public.feature`).
enum AppFeature {
  coverPage('cover_page'),
  docTemplate('doc_template'),
  questionnaire('questionnaire'),
  bibliography('bibliography'),
  export('export'),

  /// Pack Finaliste : ouvre tout.
  all('all');

  const AppFeature(this.code);

  final String code;

  static AppFeature? fromCode(String? code) {
    for (final f in values) {
      if (f.code == code) return f;
    }
    return null;
  }
}

/// Droit d'accès, copie locale d'une ligne `public.entitlements`.
///
/// La copie locale sert uniquement au fonctionnement hors ligne : elle est
/// stockée chiffrée et remplacée à chaque synchronisation. Le serveur reste
/// la seule source de vérité (RLS sur les corps des modèles payants).
class Entitlement {
  const Entitlement({
    required this.id,
    required this.feature,
    required this.startsAt,
    this.resourceId,
    this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final AppFeature feature;
  final String? resourceId;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  factory Entitlement.fromJson(Map<String, dynamic> json) => Entitlement(
        id: json['id'] as String,
        feature: AppFeature.fromCode(json['feature'] as String?) ?? AppFeature.export,
        resourceId: json['resource_id'] as String?,
        startsAt: DateTime.parse(json['starts_at'] as String),
        expiresAt: _date(json['expires_at']),
        revokedAt: _date(json['revoked_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'feature': feature.code,
        'resource_id': resourceId,
        'starts_at': startsAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'revoked_at': revokedAt?.toIso8601String(),
      };

  bool isActiveAt(DateTime now) =>
      revokedAt == null &&
      !startsAt.isAfter(now) &&
      (expiresAt == null || expiresAt!.isAfter(now));

  /// Même règle que la fonction SQL `has_access()`.
  bool grants(AppFeature wanted, String? resource, DateTime now) {
    if (!isActiveAt(now)) return false;
    if (feature == AppFeature.all) return true;
    return feature == wanted && (resourceId == null || resourceId == resource);
  }

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
}

/// Ensemble des droits de l'utilisateur.
class EntitlementSet {
  const EntitlementSet(this.items);

  static const empty = EntitlementSet([]);

  final List<Entitlement> items;

  bool hasAccess(AppFeature feature, {String? resourceId, DateTime? now}) {
    final at = now ?? DateTime.now();
    return items.any((e) => e.grants(feature, resourceId, at));
  }

  /// Date de fin du Pack Finaliste actif, s'il y en a un.
  DateTime? packExpiry({DateTime? now}) {
    final at = now ?? DateTime.now();
    DateTime? latest;
    for (final e in items) {
      if (e.feature == AppFeature.all && e.isActiveAt(at) && e.expiresAt != null) {
        if (latest == null || e.expiresAt!.isAfter(latest)) latest = e.expiresAt;
      }
    }
    return latest;
  }
}

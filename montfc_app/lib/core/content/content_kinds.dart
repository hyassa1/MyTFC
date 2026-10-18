import '../../features/store/domain/entitlement.dart';

/// Types de contenu en cache local (colonne `content_items.kind`) et leur
/// clé dans la réponse de la fonction serveur `sync_changes`.
enum ContentKind {
  institution('institutions'),
  setting('settings'),
  guideChapter('guide_chapters'),
  product('products'),
  productPrice('product_prices'),
  coverTemplate('cover_templates'),
  documentTemplate('document_templates'),
  questionnaireTemplate('questionnaire_templates');

  const ContentKind(this.syncKey);

  /// Clé dans la réponse de `sync_changes`.
  final String syncKey;
}

/// Corps des modèles payants (table locale `content_bodies`, chiffrée).
enum BodyKind {
  cover('cover_template_bodies', AppFeature.coverPage),
  document('document_template_bodies', AppFeature.docTemplate),
  questionnaire('questionnaire_template_bodies', AppFeature.questionnaire);

  const BodyKind(this.syncKey, this.feature);

  final String syncKey;

  /// Fonction à débloquer pour lire ce corps.
  final AppFeature feature;
}

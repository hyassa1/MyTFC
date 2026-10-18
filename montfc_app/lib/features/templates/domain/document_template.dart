/// Modèle de document (corps `document_template_bodies`) et plan de
/// l'étudiant. Un modèle ne contient QUE des titres et des consignes, jamais
/// de texte rédigé : c'est l'étudiant qui écrit.
library;

enum SectionKind {
  /// Pages liminaires (épigraphe, dédicace…), hors numérotation.
  preliminary,
  body,
  annex;

  static SectionKind fromCode(String? c) => switch (c) {
        'preliminary' => preliminary,
        'annex' => annex,
        _ => body,
      };
}

/// Élément du plan : titre, niveau, consignes. Sert au modèle et au plan
/// personnalisé de l'étudiant (colonne `student_works.plan`).
class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    this.kind = SectionKind.body,
    this.level = 1,
    this.numbered = true,
    this.pageBreakBefore = false,
    this.required = false,
    this.guidance,
    this.children = const [],
  });

  final String id;
  final String title;
  final SectionKind kind;

  /// 0 = hors numérotation (pages liminaires), 1 = chapitre, 2 = section…
  final int level;
  final bool numbered;
  final bool pageBreakBefore;
  final bool required;
  final String? guidance;
  final List<PlanItem> children;

  /// Lecture du modèle ou du plan enregistré. Les enfants héritent du type
  /// et prennent le niveau suivant si le modèle ne le précise pas.
  factory PlanItem.fromJson(Map<String, dynamic> j, {SectionKind? parentKind, int parentLevel = 0}) {
    final kind = j['kind'] == null && parentKind != null ? parentKind : SectionKind.fromCode(j['kind'] as String?);
    final level = (j['heading_level'] as num?)?.toInt() ?? (parentLevel + 1);
    return PlanItem(
      id: j['id'] as String,
      title: (j['title'] as String? ?? '').trim(),
      kind: kind,
      level: level,
      numbered: j['numbered'] != false,
      pageBreakBefore: j['page_break_before'] == true,
      // Dans un modèle, une sous-partie est obligatoire sauf mention contraire.
      required: j['required'] != false && (j['required'] == true || parentKind != null),
      guidance: j['guidance'] as String?,
      children: [
        for (final c in (j['children'] as List?) ?? const [])
          if (c is Map) PlanItem.fromJson(Map<String, dynamic>.from(c), parentKind: kind, parentLevel: level),
      ],
    );
  }

  static List<PlanItem> listFrom(Object? json) => [
        for (final i in (json as List?) ?? const [])
          if (i is Map && i['id'] is String) PlanItem.fromJson(Map<String, dynamic>.from(i)),
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'heading_level': level,
        if (!numbered) 'numbered': false,
        if (pageBreakBefore) 'page_break_before': true,
        'required': required,
        if (guidance != null) 'guidance': guidance,
        if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
      };

  PlanItem copyWith({String? title, List<PlanItem>? children}) => PlanItem(
        id: id,
        title: title ?? this.title,
        kind: kind,
        level: level,
        numbered: numbered,
        pageBreakBefore: pageBreakBefore,
        required: required,
        guidance: guidance,
        children: children ?? this.children,
      );
}

/// Modifications du plan (fonctions pures : l'arbre est recréé).
abstract final class PlanEdit {
  static List<PlanItem> rename(List<PlanItem> items, String id, String title) => [
        for (final i in items)
          i.id == id ? i.copyWith(title: title.trim()) : i.copyWith(children: rename(i.children, id, title)),
      ];

  /// Ajoute une sous-partie à la fin de [parentId].
  static List<PlanItem> addChild(List<PlanItem> items, String parentId, String title, String newId) => [
        for (final i in items)
          i.id == parentId
              ? i.copyWith(children: [
                  ...i.children,
                  PlanItem(id: newId, title: title.trim(), kind: i.kind, level: i.level + 1),
                ])
              : i.copyWith(children: addChild(i.children, parentId, title, newId)),
      ];

  /// Retire un élément facultatif (les éléments obligatoires restent).
  static List<PlanItem> remove(List<PlanItem> items, String id) => [
        for (final i in items)
          if (i.id != id || i.required) i.copyWith(children: remove(i.children, id)),
      ];

  /// Déplace un élément d'un cran parmi ses frères (−1 vers le haut, +1 vers le bas).
  static List<PlanItem> move(List<PlanItem> items, String id, int delta) {
    final index = items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      final target = index + delta;
      if (target < 0 || target >= items.length) return items;
      final list = List.of(items);
      list.insert(target, list.removeAt(index));
      return list;
    }
    return [for (final i in items) i.copyWith(children: move(i.children, id, delta))];
  }

  /// Nombre d'éléments, tous niveaux confondus.
  static int count(List<PlanItem> items) => items.fold(0, (n, i) => n + 1 + count(i.children));
}

/// Style d'un niveau de titre (`formatting.headings`).
class HeadingStyle {
  const HeadingStyle({
    required this.level,
    this.size = 12,
    this.bold = true,
    this.italic = false,
    this.uppercase = false,
    this.align = 'left',
    this.numbering,
  });

  final int level;
  final double size;
  final bool bold, italic, uppercase;
  final String align;

  /// Motif de numérotation : « CHAPITRE {roman} », « Section {arabic}. »,
  /// « {alpha_upper}. ».
  final String? numbering;

  factory HeadingStyle.fromJson(Map<String, dynamic> j) => HeadingStyle(
        level: (j['level'] as num).toInt(),
        size: (j['size'] as num?)?.toDouble() ?? 12,
        bold: j['bold'] != false,
        italic: j['italic'] == true,
        uppercase: j['uppercase'] == true,
        align: j['align'] as String? ?? 'left',
        numbering: j['numbering'] as String?,
      );
}

/// Normes de mise en forme d'un modèle, appliquées à l'export.
class DocFormatting {
  const DocFormatting({
    this.marginsCm = const (top: 2.5, bottom: 2.5, left: 3.0, right: 2.5),
    this.fontFamily = 'Times New Roman',
    this.fontSize = 12,
    this.lineSpacing = 1.5,
    this.align = 'justify',
    this.firstLineIndentCm = 1.25,
    this.spaceAfterPt = 6,
    this.headings = const [],
    this.footnoteSize = 10,
  });

  final ({double top, double bottom, double left, double right}) marginsCm;
  final String fontFamily;
  final double fontSize;
  final double lineSpacing;
  final String align;
  final double firstLineIndentCm;
  final double spaceAfterPt;
  final List<HeadingStyle> headings;
  final double footnoteSize;

  factory DocFormatting.fromJson(Map<String, dynamic> j) {
    double n(Object? v, double d) => v is num ? v.toDouble() : d;
    final page = (j['page'] as Map?) ?? const {};
    final m = (page['margins_cm'] as Map?) ?? const {};
    final font = (j['font'] as Map?) ?? const {};
    final p = (j['paragraph'] as Map?) ?? const {};
    return DocFormatting(
      marginsCm: (top: n(m['top'], 2.5), bottom: n(m['bottom'], 2.5), left: n(m['left'], 3), right: n(m['right'], 2.5)),
      fontFamily: font['family'] as String? ?? 'Times New Roman',
      fontSize: n(font['size'], 12),
      lineSpacing: n(j['line_spacing'], 1.5),
      align: p['align'] as String? ?? 'justify',
      firstLineIndentCm: n(p['first_line_indent_cm'], 1.25),
      spaceAfterPt: n(p['space_after_pt'], 6),
      headings: [
        for (final h in (j['headings'] as List?) ?? const [])
          if (h is Map && h['level'] is num) HeadingStyle.fromJson(Map<String, dynamic>.from(h)),
      ],
      footnoteSize: n((j['footnotes'] as Map?)?['size'], 10),
    );
  }

  HeadingStyle heading(int level) =>
      headings.where((h) => h.level == level).firstOrNull ?? HeadingStyle(level: level);

  /// Résumé des normes, en français, pour l'écran « Normes ».
  List<String> summary() {
    String cm(double v) => v.toString().replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
    return [
      'Police : $fontFamily, taille ${cm(fontSize)}',
      'Interligne : ${cm(lineSpacing)}',
      'Marges : haut ${cm(marginsCm.top)} cm, bas ${cm(marginsCm.bottom)} cm, '
          'gauche ${cm(marginsCm.left)} cm, droite ${cm(marginsCm.right)} cm',
      'Texte ${align == 'justify' ? 'justifié' : 'aligné à gauche'}, retrait de première ligne ${cm(firstLineIndentCm)} cm',
      'Notes de bas de page : taille ${cm(footnoteSize)}',
      for (final h in headings)
        'Titre de niveau ${h.level} : ${h.numbering?.replaceAll('{roman}', 'I').replaceAll('{arabic}', '1').replaceAll('{alpha_upper}', 'A').replaceAll('{alpha_lower}', 'a') ?? 'sans numéro'}'
            '${h.uppercase ? ', en majuscules' : ''}${h.bold ? ', gras' : ''}${h.italic ? ', italique' : ''}',
    ];
  }
}

/// Numérotation des titres selon les motifs du modèle (CHAPITRE I, Section 1., §1., A.).
abstract final class PlanNumbering {
  static String roman(int n) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    final b = StringBuffer();
    var rest = n;
    for (var i = 0; i < values.length; i++) {
      while (rest >= values[i]) {
        b.write(symbols[i]);
        rest -= values[i];
      }
    }
    return b.toString();
  }

  static String _alpha(int n) => String.fromCharCode(64 + ((n - 1) % 26) + 1);

  static String apply(String pattern, int n) => pattern
      .replaceAll('{roman}', roman(n))
      .replaceAll('{roman_lower}', roman(n).toLowerCase())
      .replaceAll('{arabic}', '$n')
      .replaceAll('{alpha_upper}', _alpha(n))
      .replaceAll('{alpha_lower}', _alpha(n).toLowerCase());

  /// Libellé de numéro par identifiant (absent = titre non numéroté).
  /// La numérotation des sections repart à 1 dans chaque chapitre. Les
  /// sous-parties d'une partie non numérotée (introduction générale) suivent
  /// l'usage congolais : 0.1, 0.2…
  static Map<String, String> labels(List<PlanItem> plan, DocFormatting f) {
    final out = <String, String>{};
    void walk(List<PlanItem> items, {bool zeroPrefix = false}) {
      var n = 0;
      for (final i in items) {
        final pattern = f.heading(i.level).numbering;
        if (i.kind == SectionKind.body && i.level > 0) {
          if (zeroPrefix) {
            out[i.id] = '0.${++n}.';
          } else if (i.numbered && pattern != null) {
            out[i.id] = apply(pattern, ++n);
          }
        }
        walk(i.children, zeroPrefix: i.kind == SectionKind.body && !i.numbered && i.level == 1);
      }
    }

    walk(plan);
    return out;
  }
}

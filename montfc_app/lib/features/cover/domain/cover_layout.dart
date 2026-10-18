/// Mise en page d'une page de garde (format « layout » version 1, voir
/// supabase/seed.sql). Le même modèle sert à l'aperçu, au PDF et au Word :
/// [CoverLayout.resolve] produit une page « résolue » (textes définitifs,
/// blocs conditionnels retirés) que chaque moteur dessine.
library;

const double pointsPerCm = 72 / 2.54;

enum CoverAlign { left, center, right, justify }

enum CoverBorder { none, single, double }

class CoverLayoutException implements Exception {
  const CoverLayoutException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PageMargins {
  const PageMargins({this.top = 2, this.bottom = 2, this.left = 2.5, this.right = 2});
  final double top, bottom, left, right;
}

class CoverPageSetup {
  const CoverPageSetup({this.widthCm = 21, this.heightCm = 29.7, this.margins = const PageMargins(),
      this.border = CoverBorder.none});
  final double widthCm, heightCm;
  final PageMargins margins;
  final CoverBorder border;
}

/// Bloc de la page (avant ou après résolution des champs).
sealed class CoverBlock {
  const CoverBlock({this.condition});

  /// Clé du champ qui doit être rempli pour afficher le bloc.
  final String? condition;
}

class TextBlock extends CoverBlock {
  const TextBlock({
    required this.text,
    this.align = CoverAlign.left,
    this.size,
    this.bold = false,
    this.italic = false,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 0,
    this.indentLeftRatio = 0,
    super.condition,
  });

  final String text;
  final CoverAlign align;

  /// Taille en points (null = taille de la police du modèle).
  final double? size;
  final bool bold, italic;
  final double spaceBeforePt, spaceAfterPt;

  /// Retrait à gauche, en fraction de la largeur utile (0 à 1).
  final double indentLeftRatio;

  TextBlock withText(String t) => TextBlock(
      text: t, align: align, size: size, bold: bold, italic: italic, spaceBeforePt: spaceBeforePt,
      spaceAfterPt: spaceAfterPt, indentLeftRatio: indentLeftRatio);
}

class SpacerBlock extends CoverBlock {
  const SpacerBlock(this.heightCm, {super.condition});
  final double heightCm;
}

class RuleBlock extends CoverBlock {
  const RuleBlock(this.thicknessPt, {super.condition});
  final double thicknessPt;
}

class BoxBlock extends CoverBlock {
  const BoxBlock({required this.blocks, this.border = CoverBorder.single, this.paddingCm = 0.3, super.condition});
  final List<CoverBlock> blocks;
  final CoverBorder border;
  final double paddingCm;
}

class CoverLayout {
  const CoverLayout({required this.page, required this.fontFamily, required this.fontSize, required this.blocks});

  static const supportedVersion = 1;

  final CoverPageSetup page;
  final String fontFamily;
  final double fontSize;
  final List<CoverBlock> blocks;

  factory CoverLayout.fromJson(Map<String, dynamic> j) {
    final version = (j['schema_version'] as num?)?.toInt() ?? 1;
    if (version > supportedVersion) {
      throw const CoverLayoutException(
          'Ce modèle demande une version plus récente de MonTFC. Mets l\'application à jour.');
    }
    final page = (j['page'] as Map?) ?? const {};
    final m = (page['margins_cm'] as Map?) ?? const {};
    final font = (j['font'] as Map?) ?? const {};
    final landscape = page['orientation'] == 'landscape';
    // Seul le format A4 est utilisé dans les établissements visés.
    return CoverLayout(
      page: CoverPageSetup(
        widthCm: landscape ? 29.7 : 21,
        heightCm: landscape ? 21 : 29.7,
        margins: PageMargins(
          top: _num(m['top'], 2),
          bottom: _num(m['bottom'], 2),
          left: _num(m['left'], 2.5),
          right: _num(m['right'], 2),
        ),
        border: _border(page['border']),
      ),
      fontFamily: font['family'] as String? ?? 'Times New Roman',
      fontSize: _num(font['size'], 12),
      blocks: _blocks(j['blocks']),
    );
  }

  static double _num(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

  static CoverBorder _border(Object? v) => switch (v) {
        'single' => CoverBorder.single,
        'double' => CoverBorder.double,
        _ => CoverBorder.none,
      };

  static List<CoverBlock> _blocks(Object? list) => [
        for (final b in (list as List?) ?? const [])
          if (b is Map) ?_block(Map<String, dynamic>.from(b)),
      ];

  /// Un type de bloc inconnu (ajouté plus tard) est ignoré plutôt que de tout bloquer.
  static CoverBlock? _block(Map<String, dynamic> b) {
    final cond = b['if'] as String?;
    return switch (b['type']) {
      'text' => TextBlock(
          text: b['text'] as String? ?? '',
          align: switch (b['align']) {
            'center' => CoverAlign.center,
            'right' => CoverAlign.right,
            'justify' => CoverAlign.justify,
            _ => CoverAlign.left,
          },
          size: (b['size'] as num?)?.toDouble(),
          bold: b['bold'] == true,
          italic: b['italic'] == true,
          spaceBeforePt: _num(b['space_before_pt'], 0),
          spaceAfterPt: _num(b['space_after_pt'], 0),
          indentLeftRatio: _num(b['indent_left_ratio'], 0).clamp(0, 0.9),
          condition: cond,
        ),
      'spacer' => SpacerBlock(_num(b['height_cm'], 1), condition: cond),
      'rule' => RuleBlock(_num(b['thickness_pt'], 1), condition: cond),
      'box' => BoxBlock(
          blocks: _blocks(b['blocks']),
          border: b['border'] == 'double' ? CoverBorder.double : CoverBorder.single,
          paddingCm: _num(b['padding_cm'], 0.3),
          condition: cond,
        ),
      _ => null,
    };
  }

  static final _placeholder = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)\s*(?:\|\s*(upper|lower)\s*)?\}\}');

  /// Remplace les champs {{cle}} et {{cle|upper}}. [missing] donne le texte
  /// d'un champ vide (rien à l'export, un repère dans l'aperçu).
  static String fill(String template, Map<String, String> values, {String Function(String key)? missing}) =>
      template.replaceAllMapped(_placeholder, (m) {
        final key = m.group(1)!;
        final raw = values[key]?.trim() ?? '';
        if (raw.isEmpty) return missing?.call(key) ?? '';
        return switch (m.group(2)) {
          'upper' => raw.toUpperCase(),
          'lower' => raw.toLowerCase(),
          _ => raw,
        };
      });

  /// Page résolue : blocs conditionnels retirés, textes remplis.
  List<CoverBlock> resolve(Map<String, String> values, {String Function(String key)? missing}) =>
      _resolve(blocks, values, missing);

  static List<CoverBlock> _resolve(
      List<CoverBlock> blocks, Map<String, String> values, String Function(String key)? missing) {
    bool visible(CoverBlock b) => b.condition == null || (values[b.condition]?.trim().isNotEmpty ?? false);
    return [
      for (final b in blocks)
        if (visible(b))
          switch (b) {
            TextBlock() => b.withText(fill(b.text, values, missing: missing)),
            BoxBlock() => BoxBlock(
                blocks: _resolve(b.blocks, values, missing), border: b.border, paddingCm: b.paddingCm),
            SpacerBlock() || RuleBlock() => b,
          },
    ];
  }
}

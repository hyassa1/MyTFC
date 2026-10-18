/// Document à exporter, indépendant du format : le même modèle est écrit en
/// Word (.docx) et en PDF. Les fichiers exportés appartiennent à l'étudiant,
/// sans aucune protection.
library;

import '../../bibliography/domain/styled_text.dart';

enum ExportAlign { left, center, right, justify }

enum ExportBorder { none, single, double }

enum PageNumbering { none, romanLower, arabic }

/// Bloc du document.
sealed class ExportBlock {
  const ExportBlock();
}

class ExportParagraph extends ExportBlock {
  const ExportParagraph(
    this.runs, {
    this.align = ExportAlign.left,
    this.size,
    this.bold = false,
    this.italic = false,
    this.color,
    this.indentLeftCm = 0,
    this.firstLineIndentCm = 0,
    this.hangingIndentCm = 0,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 0,
    this.lineSpacing,
    this.pageBreakBefore = false,
    this.headingLevel,
    this.box = ExportBorder.none,
    this.checkbox = false,
  });

  ExportParagraph.text(
    String text, {
    ExportAlign align = ExportAlign.left,
    double? size,
    bool bold = false,
    bool italic = false,
    String? color,
    double indentLeftCm = 0,
    double firstLineIndentCm = 0,
    double spaceBeforePt = 0,
    double spaceAfterPt = 0,
    double? lineSpacing,
    bool pageBreakBefore = false,
    int? headingLevel,
    ExportBorder box = ExportBorder.none,
    bool checkbox = false,
  }) : this(
          [StyledRun(text)],
          align: align,
          size: size,
          bold: bold,
          italic: italic,
          color: color,
          indentLeftCm: indentLeftCm,
          firstLineIndentCm: firstLineIndentCm,
          spaceBeforePt: spaceBeforePt,
          spaceAfterPt: spaceAfterPt,
          lineSpacing: lineSpacing,
          pageBreakBefore: pageBreakBefore,
          headingLevel: headingLevel,
          box: box,
          checkbox: checkbox,
        );

  final List<StyledRun> runs;
  final ExportAlign align;

  /// Taille en points (null = taille du document).
  final double? size;
  final bool bold, italic;

  /// Couleur RRGGBB (consignes en gris), null = noir.
  final String? color;
  final double indentLeftCm, firstLineIndentCm, spaceBeforePt, spaceAfterPt;

  /// Retrait négatif de première ligne (références APA) : les lignes
  /// suivantes sont décalées de cette valeur.
  final double hangingIndentCm;

  /// Interligne (1, 1.5…) ; null = celui du document.
  final double? lineSpacing;
  final bool pageBreakBefore;

  /// Titre de niveau 1 à 5 (repris dans la table des matières).
  final int? headingLevel;

  /// Paragraphe encadré (titre de la page de garde).
  final ExportBorder box;

  /// Case à cocher devant le texte (questionnaires).
  final bool checkbox;

  String get plain => runs.map((r) => r.text).join();
}

/// Espace vertical fixe.
class ExportSpacer extends ExportBlock {
  const ExportSpacer(this.heightCm);
  final double heightCm;
}

/// Filet horizontal.
class ExportRule extends ExportBlock {
  const ExportRule(this.thicknessPt);
  final double thicknessPt;
}

/// Table des matières (champ Word mis à jour à l'ouverture ; calculée dans le PDF).
class ExportToc extends ExportBlock {
  const ExportToc();
}

/// Partie du document avec sa propre mise en page et numérotation.
class ExportSection {
  const ExportSection({
    required this.blocks,
    this.numbering = PageNumbering.none,
    this.border = ExportBorder.none,
    this.margins,
    this.singlePage = false,
  });

  final List<ExportBlock> blocks;
  final PageNumbering numbering;

  /// Cadre de page (page de garde).
  final ExportBorder border;

  /// Marges propres à la partie (cm), sinon celles du document.
  final ({double top, double bottom, double left, double right})? margins;

  /// Tient sur une seule page (page de garde) : jamais coupée.
  final bool singlePage;
}

class ExportDocument {
  const ExportDocument({
    required this.title,
    required this.sections,
    this.fontSize = 12,
    this.lineSpacing = 1.15,
    this.spaceAfterPt = 0,
    this.margins = (top: 2.5, bottom: 2.5, left: 3.0, right: 2.5),
  });

  /// Titre du fichier (propriétés du document et nom proposé au partage).
  final String title;
  final List<ExportSection> sections;
  final double fontSize;
  final double lineSpacing;
  final double spaceAfterPt;
  final ({double top, double bottom, double left, double right}) margins;

  /// Nom de fichier sûr : « Page de garde - Mbuyi » → « Page_de_garde_-_Mbuyi ».
  String fileName(String extension) {
    final base = foldForSort(title)
        .replaceAll(RegExp(r'[^a-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return '${base.isEmpty ? 'montfc' : base}.$extension';
  }
}

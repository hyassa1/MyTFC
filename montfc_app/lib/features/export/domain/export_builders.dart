import '../../bibliography/domain/apa.dart';
import '../../bibliography/domain/source.dart';
import '../../cover/domain/cover_layout.dart';
import '../../questionnaires/domain/questionnaire.dart';
import '../../templates/domain/document_template.dart';
import 'export_document.dart';

/// Passage des contenus de MonTFC au document d'export.
abstract final class ExportBuilders {
  static const _guidanceColor = '7F7F7F';

  // ---------------------------------------------------------------------------
  // Page de garde
  // ---------------------------------------------------------------------------

  static ExportBorder _border(CoverBorder b) => switch (b) {
        CoverBorder.none => ExportBorder.none,
        CoverBorder.single => ExportBorder.single,
        CoverBorder.double => ExportBorder.double,
      };

  /// Section « page de garde » : une seule page, marges et cadre du modèle.
  static ExportSection coverSection(CoverLayout layout, Map<String, String> displayValues) {
    final m = layout.page.margins;
    final contentWidthCm = layout.page.widthCm - m.left - m.right;

    List<ExportBlock> map(List<CoverBlock> blocks, {ExportBorder box = ExportBorder.none}) => [
          for (final b in blocks)
            ...switch (b) {
              TextBlock() => [
                  ExportParagraph.text(
                    b.text,
                    align: switch (b.align) {
                      CoverAlign.left => ExportAlign.left,
                      CoverAlign.center => ExportAlign.center,
                      CoverAlign.right => ExportAlign.right,
                      CoverAlign.justify => ExportAlign.justify,
                    },
                    size: b.size ?? layout.fontSize,
                    bold: b.bold,
                    italic: b.italic,
                    indentLeftCm: contentWidthCm * b.indentLeftRatio,
                    spaceBeforePt: b.spaceBeforePt,
                    spaceAfterPt: b.spaceAfterPt,
                    lineSpacing: 1.15,
                    box: box,
                  ),
                ],
              SpacerBlock() => [ExportSpacer(b.heightCm)],
              RuleBlock() => [ExportRule(b.thicknessPt)],
              BoxBlock() => map(b.blocks, box: _border(b.border == CoverBorder.double ? CoverBorder.double : CoverBorder.single)),
            },
        ];

    return ExportSection(
      blocks: map(layout.resolve(displayValues)),
      border: _border(layout.page.border),
      margins: (top: m.top, bottom: m.bottom, left: m.left, right: m.right),
      singlePage: true,
    );
  }

  static ExportDocument cover(CoverLayout layout, Map<String, String> displayValues, {required String title}) =>
      ExportDocument(title: title, fontSize: layout.fontSize, sections: [coverSection(layout, displayValues)]);

  // ---------------------------------------------------------------------------
  // Bibliographie
  // ---------------------------------------------------------------------------

  static List<ExportBlock> bibliographyBlocks(Iterable<Source> sources, BibliographyOrder order,
      {double lineSpacing = 1.0}) {
    final roman = ['I', 'II', 'III', 'IV', 'V'];
    final sections = BibliographySorter.sections(sources, order);
    return [
      for (var i = 0; i < sections.length; i++) ...[
        if (sections[i].title != null)
          ExportParagraph.text('${roman[i]}. ${sections[i].title!.toUpperCase()}',
              bold: true, spaceBeforePt: i == 0 ? 6 : 12, spaceAfterPt: 6),
        for (final s in sections[i].sources)
          ExportParagraph(Apa.reference(s).runs,
              align: ExportAlign.left, hangingIndentCm: 1.27, spaceAfterPt: 6, lineSpacing: lineSpacing),
      ],
    ];
  }

  static ExportDocument bibliography(Iterable<Source> sources, BibliographyOrder order) => ExportDocument(
        title: 'Bibliographie',
        sections: [
          ExportSection(numbering: PageNumbering.arabic, blocks: [
            ExportParagraph.text('BIBLIOGRAPHIE', align: ExportAlign.center, bold: true, size: 14, spaceAfterPt: 12,
                headingLevel: 1),
            ...bibliographyBlocks(sources, order),
          ]),
        ],
      );

  // ---------------------------------------------------------------------------
  // Questionnaire
  // ---------------------------------------------------------------------------

  static ExportDocument questionnaire(FinalQuestionnaire q, {required String title}) {
    final blocks = <ExportBlock>[
      ExportParagraph.text('QUESTIONNAIRE D\'ENQUÊTE', align: ExportAlign.center, bold: true, size: 14),
      ExportParagraph.text(title, align: ExportAlign.center, italic: true, spaceAfterPt: 12),
      if (q.intro != null)
        for (final line in q.intro!.split('\n')) ExportParagraph.text(line, align: ExportAlign.justify, spaceAfterPt: 6),
    ];
    for (final s in q.sections) {
      blocks.add(ExportParagraph.text(s.title.toUpperCase(), bold: true, spaceBeforePt: 12, spaceAfterPt: 6));
      for (final (:number, :question) in s.questions) {
        final hint = switch (question.type) {
          QuestionType.multiple => ' (plusieurs réponses possibles)',
          _ => '',
        };
        blocks.add(ExportParagraph.text('$number. ${question.text}${question.text.contains('plusieurs') ? '' : hint}',
            bold: true, spaceBeforePt: 6, spaceAfterPt: 2));
        switch (question.type) {
          case QuestionType.single || QuestionType.multiple || QuestionType.scale:
            for (final o in question.options) {
              blocks.add(ExportParagraph.text(o, indentLeftCm: 0.8, checkbox: true));
            }
          case QuestionType.number:
            blocks.add(ExportParagraph.text('Réponse : ……………………', indentLeftCm: 0.8));
          case QuestionType.open:
            for (var i = 0; i < 3; i++) {
              blocks.add(ExportParagraph.text('……………………………………………………………………………………………', indentLeftCm: 0.8,
                  spaceBeforePt: 4));
            }
        }
      }
    }
    if (q.closing != null) {
      blocks.add(ExportParagraph.text(q.closing!, align: ExportAlign.center, italic: true, spaceBeforePt: 18));
    }
    return ExportDocument(
      title: 'Questionnaire - $title',
      margins: (top: 2, bottom: 2, left: 2, right: 2),
      sections: [ExportSection(numbering: PageNumbering.arabic, blocks: blocks)],
    );
  }

  // ---------------------------------------------------------------------------
  // Travail complet : page de garde, plan, consignes, bibliographie, table
  // ---------------------------------------------------------------------------

  /// Squelette du travail aux normes du modèle. Aucun texte rédigé : sous
  /// chaque titre, la consigne en gris (à effacer) et la place pour écrire.
  static ExportDocument work({
    required String title,
    required List<PlanItem> plan,
    required DocFormatting formatting,
    ExportSection? cover,
    Iterable<Source> sources = const [],
    BibliographyOrder order = BibliographyOrder.byKind,
  }) {
    final labels = PlanNumbering.labels(plan, formatting);
    final f = formatting;

    ExportAlign align(String a) => switch (a) {
          'center' => ExportAlign.center,
          'right' => ExportAlign.right,
          'justify' => ExportAlign.justify,
          _ => ExportAlign.left,
        };

    ExportParagraph heading(PlanItem item, {bool pageBreak = false}) {
      final style = f.heading(item.level == 0 ? 1 : item.level);
      final label = labels[item.id];
      final titleText = style.uppercase || item.level <= 1 ? item.title.toUpperCase() : item.title;
      final text = label == null
          ? titleText
          : item.level == 1
              ? '$label\n$titleText'
              : '$label $titleText';
      return ExportParagraph.text(
        text,
        headingLevel: item.level == 0 ? null : item.level.clamp(1, 5),
        size: style.size,
        bold: style.bold,
        italic: style.italic,
        align: item.level <= 1 ? ExportAlign.center : align(style.align),
        pageBreakBefore: pageBreak,
        spaceBeforePt: item.level <= 1 ? 0 : 12,
        spaceAfterPt: item.level <= 1 ? 18 : 6,
      );
    }

    ExportParagraph guidance(String text) => ExportParagraph.text('[Consigne à effacer : $text]',
        italic: true, color: _guidanceColor, size: f.fontSize - 1, align: align(f.align), spaceAfterPt: f.spaceAfterPt);

    ExportParagraph writingSpace() => ExportParagraph.text('',
        align: align(f.align), firstLineIndentCm: f.firstLineIndentCm, spaceAfterPt: f.spaceAfterPt);

    List<ExportBlock> body(List<PlanItem> items) {
      final out = <ExportBlock>[];
      for (final item in items) {
        if (item.kind == SectionKind.annex && item.id == 'bibliographie') {
          out.add(heading(item, pageBreak: true));
          out.addAll(sources.isEmpty
              ? [guidance(item.guidance ?? 'Ajoute tes sources dans MonTFC.')]
              : bibliographyBlocks(sources, order, lineSpacing: 1.0));
          continue;
        }
        if (item.kind == SectionKind.annex && item.id == 'table-matieres') {
          out
            ..add(heading(item, pageBreak: true))
            ..add(const ExportToc());
          continue;
        }
        out.add(heading(item, pageBreak: item.level <= 1 && (item.pageBreakBefore || item.level == 1)));
        if (item.guidance != null) out.add(guidance(item.guidance!));
        if (item.children.isEmpty) out.add(writingSpace());
        out.addAll(body(item.children));
      }
      return out;
    }

    final preliminary = plan.where((i) => i.kind == SectionKind.preliminary).toList();
    final rest = plan.where((i) => i.kind != SectionKind.preliminary).toList();
    return ExportDocument(
      title: title,
      fontSize: f.fontSize,
      lineSpacing: f.lineSpacing,
      spaceAfterPt: f.spaceAfterPt,
      margins: f.marginsCm,
      sections: [
        ?cover,
        if (preliminary.isNotEmpty)
          ExportSection(numbering: PageNumbering.romanLower, blocks: [
            for (var i = 0; i < preliminary.length; i++) ...[
              heading(preliminary[i], pageBreak: i > 0),
              if (preliminary[i].guidance != null) guidance(preliminary[i].guidance!),
              writingSpace(),
            ],
          ]),
        if (rest.isNotEmpty) ExportSection(numbering: PageNumbering.arabic, blocks: body(rest)),
      ],
    );
  }
}

/// Raccourci pour les tests : texte brut d'un bloc.
String exportPlain(ExportBlock b) => switch (b) {
      ExportParagraph() => b.plain,
      ExportSpacer() => '',
      ExportRule() => '―',
      ExportToc() => '[TABLE DES MATIÈRES]',
    };

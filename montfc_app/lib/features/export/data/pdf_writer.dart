import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../templates/domain/document_template.dart';
import '../domain/export_document.dart';

/// Polices du PDF (Liberation Serif, mêmes dimensions que Times New Roman).
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold, required this.italic, required this.boldItalic});

  final pw.Font regular, bold, italic, boldItalic;

  factory PdfFonts.fromBytes({
    required ByteData regular,
    required ByteData bold,
    required ByteData italic,
    required ByteData boldItalic,
  }) =>
      PdfFonts(
        regular: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        italic: pw.Font.ttf(italic),
        boldItalic: pw.Font.ttf(boldItalic),
      );

  static const assetPaths = (
    regular: 'assets/fonts/LiberationSerif-Regular.ttf',
    bold: 'assets/fonts/LiberationSerif-Bold.ttf',
    italic: 'assets/fonts/LiberationSerif-Italic.ttf',
    boldItalic: 'assets/fonts/LiberationSerif-BoldItalic.ttf',
  );
}

/// Écrit un [ExportDocument] en PDF, avec la même mise en page que le Word.
class PdfWriter {
  PdfWriter(this.fonts);

  final PdfFonts fonts;

  static double _cm(double v) => v * PdfPageFormat.cm;

  Future<Uint8List> write(ExportDocument doc) async {
    final pdf = pw.Document(title: doc.title, creator: 'MonTFC', author: null);
    final theme = pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
      italic: fonts.italic,
      boldItalic: fonts.boldItalic,
    ).copyWith(defaultTextStyle: pw.TextStyle(font: fonts.regular, fontSize: doc.fontSize));

    for (final section in doc.sections) {
      final m = section.margins ?? doc.margins;
      final format = PdfPageFormat.a4.copyWith(
        marginTop: _cm(m.top),
        marginBottom: _cm(m.bottom),
        marginLeft: _cm(m.left),
        marginRight: _cm(m.right),
      );
      final widgets = _widgets(doc, section.blocks);

      if (section.singlePage) {
        pdf.addPage(pw.Page(
          pageFormat: format,
          theme: theme,
          build: (_) {
            final content = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: widgets);
            return _framed(section.border, content);
          },
        ));
        continue;
      }

      // Numérotation propre à la partie (i, ii… pour les pages liminaires).
      int? firstPage;
      pdf.addPage(pw.MultiPage(
        pageFormat: format,
        theme: theme,
        footer: section.numbering == PageNumbering.none
            ? null
            : (context) {
                firstPage ??= context.pageNumber;
                final n = context.pageNumber - firstPage! + 1;
                return pw.Center(
                  child: pw.Text(
                    section.numbering == PageNumbering.romanLower ? PlanNumbering.roman(n).toLowerCase() : '$n',
                    style: pw.TextStyle(fontSize: doc.fontSize - 1),
                  ),
                );
              },
        build: (_) => widgets,
      ));
    }
    return pdf.save();
  }

  pw.Widget _framed(ExportBorder border, pw.Widget child) {
    if (border == ExportBorder.none) return child;
    final inner = pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      padding: pw.EdgeInsets.all(_cm(0.3)),
      child: child,
    );
    if (border == ExportBorder.single) return pw.SizedBox.expand(child: inner);
    return pw.SizedBox.expand(
      child: pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.6)),
        padding: const pw.EdgeInsets.all(2),
        child: inner,
      ),
    );
  }

  List<pw.Widget> _widgets(ExportDocument doc, List<ExportBlock> blocks) {
    final out = <pw.Widget>[];
    var i = 0;
    while (i < blocks.length) {
      final b = blocks[i];
      // Paragraphes encadrés consécutifs : un seul cadre (comme dans Word).
      if (b is ExportParagraph && b.box != ExportBorder.none) {
        final group = <ExportParagraph>[];
        while (i < blocks.length && blocks[i] is ExportParagraph && (blocks[i] as ExportParagraph).box == b.box) {
          group.add(blocks[i] as ExportParagraph);
          i++;
        }
        out.add(pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          padding: pw.EdgeInsets.all(_cm(0.3)),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: b.box == ExportBorder.double ? 2.2 : 0.8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [for (final p in group) _paragraph(doc, p)],
          ),
        ));
        continue;
      }
      // Saut de page : seulement entre deux blocs de premier niveau.
      if (b is ExportParagraph && b.pageBreakBefore && out.isNotEmpty) out.add(pw.NewPage());
      out.add(switch (b) {
        ExportParagraph() => _paragraph(doc, b),
        ExportSpacer() => pw.SizedBox(height: _cm(b.heightCm)),
        ExportRule() => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Container(height: b.thicknessPt, color: PdfColors.black),
          ),
        ExportToc() => pw.TableOfContent(),
      });
      i++;
    }
    return out;
  }

  pw.Widget _paragraph(ExportDocument doc, ExportParagraph p) {
    final size = p.size ?? doc.fontSize;
    // Interligne Word « 1,5 » ≈ 1,5 × 1,15 × la taille ; le PDF ajoute l'écart.
    final extra = size * ((p.lineSpacing ?? doc.lineSpacing) * 1.15 - 1).clamp(0, 3);
    final color = p.color == null ? PdfColors.black : PdfColor.fromHex(p.color!);
    pw.TextStyle style(bool italic) => pw.TextStyle(
          fontSize: size,
          fontWeight: p.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: italic || p.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          color: color,
          lineSpacing: extra,
        );

    final align = switch (p.align) {
      ExportAlign.left => pw.TextAlign.left,
      ExportAlign.center => pw.TextAlign.center,
      ExportAlign.right => pw.TextAlign.right,
      ExportAlign.justify => pw.TextAlign.justify,
    };

    pw.Widget text = pw.RichText(
      textAlign: align,
      text: pw.TextSpan(children: [
        if (p.firstLineIndentCm > 0) pw.WidgetSpan(child: pw.SizedBox(width: _cm(p.firstLineIndentCm))),
        for (final r in p.runs) pw.TextSpan(text: r.text, style: style(r.italic)),
        // Paragraphe vide : garde sa hauteur (place pour écrire).
        if (p.plain.isEmpty) pw.TextSpan(text: ' ', style: style(false)),
      ]),
    );

    // Pleine largeur : centrage et justification par rapport à la page.
    text = pw.SizedBox(width: double.infinity, child: text);

    if (p.checkbox) {
      text = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: size * 0.7,
          height: size * 0.7,
          margin: pw.EdgeInsets.only(top: size * 0.2, right: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
        ),
        pw.Expanded(child: text),
      ]);
    }

    final padded = pw.Padding(
      padding: pw.EdgeInsets.only(
        left: _cm(p.indentLeftCm + p.hangingIndentCm),
        top: p.spaceBeforePt,
        bottom: p.spaceAfterPt,
      ),
      child: text,
    );

    if (p.headingLevel == null) return padded;
    // Titre : repris dans la table des matières du PDF.
    return pw.Header(
      level: p.headingLevel!.clamp(0, 5),
      title: p.plain.replaceAll('\n', ' : '),
      decoration: const pw.BoxDecoration(),
      padding: pw.EdgeInsets.zero,
      margin: pw.EdgeInsets.zero,
      child: padded,
    );
  }
}

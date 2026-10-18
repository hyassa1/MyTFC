import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/export_document.dart';

/// Écrit un [ExportDocument] au format Word (.docx, Office Open XML).
///
/// Écriture directe du XML, sans dépendance lourde : styles « Titre 1 » à
/// « Titre 5 » (repris par la table des matières de Word), sections avec
/// numérotation de pages propre (romains pour les pages liminaires, arabes
/// pour le corps), cadre de page pour la page de garde.
class DocxWriter {
  DocxWriter({this.fontFamily = 'Times New Roman', DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Police demandée par les établissements ; Word l'a toujours.
  final String fontFamily;
  final DateTime Function() _clock;

  static int _twips(double cm) => (cm * 1440 / 2.54).round();

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Uint8List write(ExportDocument doc) {
    final archive = Archive();
    void add(String name, String content) => archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _rootRels);
    add('docProps/core.xml', _core(doc.title));
    add('docProps/app.xml', _app);
    add('word/_rels/document.xml.rels', _documentRels);
    add('word/styles.xml', _styles(doc));
    add('word/settings.xml', _settings);
    add('word/footer1.xml', _footer);
    add('word/document.xml', _document(doc));
    return ZipEncoder().encodeBytes(archive);
  }

  // ---------------------------------------------------------------------------
  // Corps du document
  // ---------------------------------------------------------------------------

  String _document(ExportDocument doc) {
    final body = StringBuffer();
    for (var i = 0; i < doc.sections.length; i++) {
      final section = doc.sections[i];
      final sectPr = _sectPr(doc, section);
      final isLast = i == doc.sections.length - 1;
      final blocks = section.blocks.isEmpty ? const <ExportBlock>[ExportSpacer(0.1)] : section.blocks;
      for (var b = 0; b < blocks.length; b++) {
        // Les propriétés d'une section se placent dans son dernier paragraphe ;
        // celles de la dernière section, à la fin du corps.
        final attachSect = !isLast && b == blocks.length - 1;
        body.write(_block(doc, blocks[b], sectPr: attachSect ? sectPr : null));
      }
      if (isLast) body.write(sectPr);
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<w:body>$body</w:body></w:document>';
  }

  String _sectPr(ExportDocument doc, ExportSection s) {
    final m = s.margins ?? doc.margins;
    final b = StringBuffer('<w:sectPr>');
    if (s.numbering != PageNumbering.none) b.write('<w:footerReference w:type="default" r:id="rIdFooter1"/>');
    b.write('<w:type w:val="nextPage"/>');
    b.write('<w:pgSz w:w="11906" w:h="16838"/>');
    b.write('<w:pgMar w:top="${_twips(m.top)}" w:right="${_twips(m.right)}" w:bottom="${_twips(m.bottom)}" '
        'w:left="${_twips(m.left)}" w:header="709" w:footer="709" w:gutter="0"/>');
    if (s.border != ExportBorder.none) {
      final val = s.border == ExportBorder.double ? 'double' : 'single';
      final sz = s.border == ExportBorder.double ? 6 : 8;
      b.write('<w:pgBorders w:offsetFrom="text">');
      for (final side in ['top', 'left', 'bottom', 'right']) {
        b.write('<w:$side w:val="$val" w:sz="$sz" w:space="8" w:color="000000"/>');
      }
      b.write('</w:pgBorders>');
    }
    switch (s.numbering) {
      case PageNumbering.romanLower:
        b.write('<w:pgNumType w:fmt="lowerRoman" w:start="1"/>');
      case PageNumbering.arabic:
        b.write('<w:pgNumType w:fmt="decimal" w:start="1"/>');
      case PageNumbering.none:
        break;
    }
    b.write('</w:sectPr>');
    return b.toString();
  }

  String _block(ExportDocument doc, ExportBlock block, {String? sectPr}) {
    switch (block) {
      case ExportParagraph():
        return _paragraph(doc, block, sectPr: sectPr);
      case ExportSpacer():
        final h = _twips(block.heightCm).clamp(20, 31680);
        return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="$h" w:lineRule="exact"/>'
            '${sectPr ?? ''}</w:pPr></w:p>';
      case ExportRule():
        final sz = (block.thicknessPt * 8).round().clamp(2, 96);
        return '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="$sz" w:space="1" w:color="000000"/></w:pBdr>'
            '<w:spacing w:before="60" w:after="60" w:line="120" w:lineRule="exact"/>${sectPr ?? ''}</w:pPr></w:p>';
      case ExportToc():
        // Champ TOC : Word le remplit à l'ouverture (updateFields dans settings.xml).
        return '<w:p><w:pPr>${sectPr ?? ''}</w:pPr>'
            '<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>'
            '<w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h \\z \\u </w:instrText></w:r>'
            '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
            '<w:r><w:t xml:space="preserve">Mets à jour la table des matières : clic droit ici, puis « Mettre à jour les champs ».</w:t></w:r>'
            '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>';
    }
  }

  String _paragraph(ExportDocument doc, ExportParagraph p, {String? sectPr}) {
    final ppr = StringBuffer('<w:pPr>');
    if (p.headingLevel != null) ppr.write('<w:pStyle w:val="Heading${p.headingLevel!.clamp(1, 5)}"/>');
    if (p.headingLevel != null) ppr.write('<w:keepNext/>');
    if (p.pageBreakBefore) ppr.write('<w:pageBreakBefore/>');
    if (p.box != ExportBorder.none) {
      final val = p.box == ExportBorder.double ? 'double' : 'single';
      ppr.write('<w:pBdr>');
      for (final side in ['top', 'left', 'bottom', 'right']) {
        ppr.write('<w:$side w:val="$val" w:sz="8" w:space="4" w:color="000000"/>');
      }
      ppr.write('</w:pBdr>');
    }
    final line = ((p.lineSpacing ?? doc.lineSpacing) * 240).round();
    ppr.write('<w:spacing w:before="${(p.spaceBeforePt * 20).round()}" w:after="${(p.spaceAfterPt * 20).round()}" '
        'w:line="$line" w:lineRule="auto"/>');
    if (p.hangingIndentCm > 0) {
      ppr.write('<w:ind w:left="${_twips(p.indentLeftCm + p.hangingIndentCm)}" '
          'w:hanging="${_twips(p.hangingIndentCm)}"/>');
    } else if (p.indentLeftCm > 0 || p.firstLineIndentCm > 0) {
      ppr.write('<w:ind w:left="${_twips(p.indentLeftCm)}"'
          '${p.firstLineIndentCm > 0 ? ' w:firstLine="${_twips(p.firstLineIndentCm)}"' : ''}/>');
    }
    ppr.write('<w:jc w:val="${switch (p.align) {
      ExportAlign.left => 'left',
      ExportAlign.center => 'center',
      ExportAlign.right => 'right',
      ExportAlign.justify => 'both',
    }}"/>');
    ppr.write(sectPr ?? '');
    ppr.write('</w:pPr>');

    final runs = StringBuffer();
    final size = ((p.size ?? doc.fontSize) * 2).round();
    String rpr({required bool italic, String? font}) => '<w:rPr>'
        '<w:rFonts w:ascii="${font ?? fontFamily}" w:hAnsi="${font ?? fontFamily}" w:cs="${font ?? fontFamily}"/>'
        '${p.bold ? '<w:b/><w:bCs/>' : ''}${italic ? '<w:i/><w:iCs/>' : ''}'
        '${p.color != null ? '<w:color w:val="${p.color}"/>' : ''}'
        '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>';
    if (p.checkbox) runs.write('<w:r>${rpr(italic: false, font: 'Segoe UI Symbol')}<w:t xml:space="preserve">☐ </w:t></w:r>');
    for (final r in p.runs) {
      final lines = r.text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        runs.write('<w:r>${rpr(italic: r.italic || p.italic)}');
        if (i > 0) runs.write('<w:br/>');
        runs.write('<w:t xml:space="preserve">${_esc(lines[i])}</w:t></w:r>');
      }
    }
    return '<w:p>$ppr$runs</w:p>';
  }

  // ---------------------------------------------------------------------------
  // Parties fixes du paquet
  // ---------------------------------------------------------------------------

  String _styles(ExportDocument doc) {
    final size = (doc.fontSize * 2).round();
    final line = (doc.lineSpacing * 240).round();
    final headings = StringBuffer();
    for (var l = 1; l <= 5; l++) {
      headings.write('<w:style w:type="paragraph" w:styleId="Heading$l"><w:name w:val="heading $l"/>'
          '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>'
          '<w:pPr><w:keepNext/><w:outlineLvl w:val="${l - 1}"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="$fontFamily" w:hAnsi="$fontFamily" w:cs="$fontFamily" w:eastAsia="$fontFamily"/>'
        '<w:sz w:val="$size"/><w:szCs w:val="$size"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="${(doc.spaceAfterPt * 20).round()}" w:line="$line" '
        'w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
        '$headings'
        '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/></w:style>'
        '</w:styles>';
  }

  static const _footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:p><w:pPr><w:pStyle w:val="Footer"/><w:jc w:val="center"/></w:pPr>'
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
      '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r>'
      '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:ftr>';

  static const _settings = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:updateFields w:val="true"/><w:defaultTabStop w:val="709"/>'
      '<w:characterSpacingControl w:val="doNotCompress"/><w:themeFontLang w:val="fr-FR"/></w:settings>';

  static const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/settings.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '<Override PartName="/word/footer1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '</Types>';

  static const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
      'Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" '
      'Target="docProps/app.xml"/>'
      '</Relationships>';

  static const _documentRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>'
      '<Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" '
      'Target="settings.xml"/>'
      '<Relationship Id="rIdFooter1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" '
      'Target="footer1.xml"/>'
      '</Relationships>';

  static const _app = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>MonTFC</Application></Properties>';

  String _core(String title) {
    final now = _clock().toUtc().toIso8601String().split('.').first;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_esc(title)}</dc:title><dc:language>fr-FR</dc:language>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified>'
        '</cp:coreProperties>';
  }
}

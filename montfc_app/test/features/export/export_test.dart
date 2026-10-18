import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:montfc/features/bibliography/domain/apa.dart';
import 'package:montfc/features/bibliography/domain/source.dart';
import 'package:montfc/features/cover/domain/cover_fields.dart';
import 'package:montfc/features/export/data/docx_writer.dart';
import 'package:montfc/features/export/data/export_service.dart';
import 'package:montfc/features/export/data/pdf_writer.dart';
import 'package:montfc/features/export/domain/export_builders.dart';
import 'package:montfc/features/export/domain/export_document.dart';
import 'package:montfc/features/questionnaires/domain/questionnaire.dart';
import 'package:montfc/features/templates/domain/document_template.dart';
import 'package:xml/xml.dart';

import '../cover/cover_test_data.dart';

/// Dossier où écrire les fichiers pour les ouvrir à la main (facultatif) :
/// MONTFC_EXPORT_DIR=/tmp/exports flutter test test/features/export
final outDir = Platform.environment['MONTFC_EXPORT_DIR'];

void save(String name, List<int> bytes) {
  if (outDir == null) return;
  Directory(outDir!).createSync(recursive: true);
  File('$outDir/$name').writeAsBytesSync(bytes);
}

PdfFonts testFonts() {
  ByteData load(String path) => ByteData.sublistView(File(path).readAsBytesSync());
  final p = PdfFonts.assetPaths;
  return PdfFonts.fromBytes(
      regular: load(p.regular), bold: load(p.bold), italic: load(p.italic), boldItalic: load(p.boldItalic));
}

Map<String, String> unzip(List<int> bytes) => {
      for (final f in ZipDecoder().decodeBytes(bytes)) f.name: utf8.decode(f.content as List<int>),
    };

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  final values = {
    'faculty': 'Sciences économiques et de gestion',
    'department': 'Gestion financière',
    'title': 'L\'impact du mobile money sur l\'épargne des ménages à Kinshasa',
    'student_name': 'Mbuyi Kalala Jean',
    'grade': 'memoire_licence',
    'discipline': 'gestion financière',
    'director': 'Prof. Lukusa',
    'supervisor': 'C.T. Ilunga',
    'academic_year': '2025-2026',
  };
  final fields = CoverField.listFrom(coverTemplates().firstWhere((t) => t['id'] == unikinId)['fields_schema']);
  final display = CoverForm.displayValues(fields, values);

  final doc = jsonDecode(File('test/fixtures/document_template.json').readAsStringSync()) as Map<String, dynamic>;
  final plan = PlanItem.listFrom(doc['structure']);
  final formatting = DocFormatting.fromJson(doc['formatting'] as Map<String, dynamic>);
  final sources = [
    const Source(id: '1', kind: SourceKind.book, authors: [Person(last: 'Mbuyi', first: 'Jean-Pierre')],
        year: '2015', title: 'Œuvres économiques', publisher: 'PUK', place: 'Kinshasa'),
    const Source(id: '2', kind: SourceKind.article, authors: [Person(last: 'Kalala', first: 'Paul')], year: '2021',
        title: 'Microfinance « inclusive »', journal: 'Revue congolaise de gestion', volume: '12', issue: '3',
        pages: '101-120'),
  ];

  ExportDocument work() => ExportBuilders.work(
        title: 'Mémoire - Mbuyi',
        plan: plan,
        formatting: formatting,
        cover: ExportBuilders.coverSection(layout(unikinId), display),
        sources: sources,
      );

  group('Word', () {
    test('page de garde : cadre double, marges du modèle, texte en majuscules, une seule section', () {
      final bytes = DocxWriter(clock: () => DateTime.utc(2026, 10, 18))
          .write(ExportBuilders.cover(layout(unikinId), display, title: 'Page de garde'));
      save('page_de_garde.docx', bytes);
      final files = unzip(bytes);
      expect(files.keys, containsAll(['[Content_Types].xml', 'word/document.xml', 'word/styles.xml', '_rels/.rels']));

      final xml = XmlDocument.parse(files['word/document.xml']!);
      final text = xml.findAllElements('w:t').map((e) => e.innerText).join('|');
      expect(text, contains('UNIVERSITÉ DE KINSHASA'));
      expect(text, contains('L\'IMPACT DU MOBILE MONEY SUR L\'ÉPARGNE DES MÉNAGES À KINSHASA'));
      expect(text, contains('Mémoire présenté et défendu en vue de l\'obtention du grade de licencié en gestion financière'));
      expect(xml.findAllElements('w:sectPr'), hasLength(1));
      expect(xml.findAllElements('w:pgBorders').single.findElements('w:top').single.getAttribute('w:val'), 'double');
      expect(xml.findAllElements('w:pgMar').single.getAttribute('w:left'), '1417', reason: '2,5 cm');
      expect(xml.findAllElements('w:footerReference'), isEmpty, reason: 'pas de numéro sur la page de garde');
      XmlDocument.parse(files['word/styles.xml']!);
    });

    test('travail complet : 3 sections, numérotation romaine puis arabe, titres pour la table, consignes en gris',
        () {
      final bytes = DocxWriter().write(work());
      save('memoire_squelette.docx', bytes);
      final xml = XmlDocument.parse(unzip(bytes)['word/document.xml']!);

      final sects = xml.findAllElements('w:sectPr').toList();
      expect(sects, hasLength(3));
      expect(sects[1].findElements('w:pgNumType').single.getAttribute('w:fmt'), 'lowerRoman');
      expect(sects[2].findElements('w:pgNumType').single.getAttribute('w:fmt'), 'decimal');
      expect(sects[2].findElements('w:pgMar').single.getAttribute('w:left'), '1701', reason: '3 cm du modèle');

      final headings = xml
          .findAllElements('w:p')
          .where((p) => p.findAllElements('w:pStyle').any((s) => s.getAttribute('w:val') == 'Heading1'))
          .map((p) => p.findAllElements('w:t').map((t) => t.innerText).join(' '))
          .toList();
      expect(headings, contains('CHAPITRE I CONSIDÉRATIONS GÉNÉRALES (CADRE CONCEPTUEL ET THÉORIQUE)'));
      expect(headings, contains('INTRODUCTION GÉNÉRALE'));

      final all = xml.findAllElements('w:t').map((e) => e.innerText).join('\n');
      expect(all, contains('0.2. Problématique'));
      expect(all, contains('[Consigne à effacer : '));
      expect(all, contains('Œuvres économiques'));
      expect(xml.findAllElements('w:instrText').map((e) => e.innerText).join(), contains('TOC'));
      expect(xml.findAllElements('w:color').first.getAttribute('w:val'), '7F7F7F');
      // Référence APA : retrait négatif.
      expect(xml.findAllElements('w:ind').any((i) => i.getAttribute('w:hanging') == '720'), isTrue);
    });

    test('caractères spéciaux échappés', () {
      final bytes = DocxWriter().write(ExportDocument(title: 'x', sections: [
        ExportSection(blocks: [ExportParagraph.text('A & B < C > "D"\nligne 2')]),
      ]));
      final xml = XmlDocument.parse(unzip(bytes)['word/document.xml']!);
      expect(xml.findAllElements('w:t').map((e) => e.innerText).join('|'), 'A & B < C > "D"|ligne 2');
      expect(xml.findAllElements('w:br'), hasLength(1));
    });
  });

  group('PDF', () {
    test('page de garde, travail complet, bibliographie, questionnaire : accents et guillemets', () async {
      final writer = PdfWriter(testFonts());
      final cover = await writer.write(ExportBuilders.cover(layout(unikinId), display, title: 'Page de garde'));
      final full = await writer.write(work());
      final biblio = await writer.write(ExportBuilders.bibliography(sources, BibliographyOrder.byKind));
      final q = QuestionnaireTemplate.fromJson(
          jsonDecode(File('test/fixtures/questionnaire.json').readAsStringSync()) as Map<String, dynamic>);
      final quest = await writer.write(ExportBuilders.questionnaire(
          FinalQuestionnaire.build(q, const QuestionnaireDraft(values: {'organisation': 'la SNEL'})),
          title: 'Satisfaction'));
      save('page_de_garde.pdf', cover);
      save('memoire_squelette.pdf', full);
      save('bibliographie.pdf', biblio);
      save('questionnaire.pdf', quest);

      for (final pdf in [cover, full, biblio, quest]) {
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      }
      // Polices embarquées (pas les polices standard limitées au Latin-1).
      expect(latin1.decode(cover, allowInvalid: true), contains('LiberationSerif'));
    });

    test('titre très long : la page de garde reste sur une page', () async {
      final long = {...display, 'title': List.filled(30, 'Un titre beaucoup trop long').join(' ')};
      final pdf = await PdfWriter(testFonts()).write(ExportBuilders.cover(layout(unikinId), long, title: 'x'));
      expect(RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(pdf, allowInvalid: true)).length, 1);
    });
  });

  test('nom de fichier sûr', () {
    expect(const ExportDocument(title: 'Mémoire - Mbuyi Kalala', sections: []).fileName('docx'),
        'memoire_-_mbuyi_kalala.docx');
    expect(const ExportDocument(title: '«»', sections: []).fileName('pdf'), 'montfc.pdf');
  });

  test('service : fichier Word et PDF écrits dans le dossier temporaire', () async {
    final tmp = await Directory.systemTemp.createTemp('montfc');
    addTearDown(() => tmp.delete(recursive: true));
    final service = ExportService(
      directory: () async => tmp,
      loadAsset: (path) async => ByteData.sublistView(File(path).readAsBytesSync()),
    );
    final doc = ExportBuilders.bibliography(sources, BibliographyOrder.alphabetical);
    final docx = await service.save(doc, ExportFormat.docx);
    final pdf = await service.save(doc, ExportFormat.pdf);
    // Séparateurs normalisés : Windows renvoie « exports\bibliographie.docx ».
    expect(docx.path.replaceAll(r'\', '/'), endsWith('exports/bibliographie.docx'));
    expect(pdf.lengthSync(), greaterThan(1000));
  });
}

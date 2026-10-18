import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:montfc/features/bibliography/domain/apa.dart';
import 'package:montfc/features/bibliography/domain/source.dart';

const mbuyi = Person(last: 'Mbuyi', first: 'Jean-Pierre');
const kalala = Person(last: 'Kalala', first: 'Paul Marie');
const ilunga = Person(last: 'Ilunga', first: 'Marie');

Source book({List<Person> authors = const [mbuyi], String? edition, String? year = '2015'}) => Source(
      id: 'b1',
      kind: SourceKind.book,
      authors: authors,
      year: year,
      title: 'La gestion financière des PME',
      subtitle: 'cas de Kinshasa',
      edition: edition,
      publisher: 'Presses universitaires de Kinshasa',
      place: 'Kinshasa',
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr'));

  group('APA 7 : auteurs', () {
    test('initiales : prénoms composés et multiples', () {
      expect(mbuyi.initials, 'J.-P.');
      expect(kalala.initials, 'P. M.');
      expect(const Person(last: 'Nkulu').initials, '');
    });

    test('1, 2, 3 auteurs ; au-delà de 20 : 19 premiers, …, le dernier', () {
      expect(Apa.authorList([mbuyi]), 'Mbuyi, J.-P.');
      expect(Apa.authorList([mbuyi, kalala]), 'Mbuyi, J.-P. et Kalala, P. M.');
      expect(Apa.authorList([mbuyi, kalala, ilunga]), 'Mbuyi, J.-P., Kalala, P. M. et Ilunga, M.');
      final many = [for (var i = 1; i <= 22; i++) Person(last: 'A$i', first: 'B')];
      final list = Apa.authorList(many);
      expect(list, startsWith('A1, B., A2, B.'));
      expect(list, contains('A19, B., . . . A22, B.'));
      expect(list, isNot(contains('A20')));
    });
  });

  group('APA 7 : références', () {
    test('ouvrage : titre en italique, édition, éditeur, sans lieu', () {
      final r = Apa.reference(book(edition: '2'));
      expect(r.markdown,
          'Mbuyi, J.-P. (2015). *La gestion financière des PME : cas de Kinshasa* (2e éd.). '
          'Presses universitaires de Kinshasa.');
    });

    test('ouvrage sans date : (s.d.)', () {
      expect(Apa.reference(book(year: null)).plain, contains('(s.d.).'));
    });

    test('ouvrage sans auteur : le titre prend la place de l\'auteur', () {
      expect(Apa.reference(book(authors: const [])).markdown,
          '*La gestion financière des PME : cas de Kinshasa*. (2015). Presses universitaires de Kinshasa.');
    });

    test('chapitre dans un ouvrage collectif', () {
      const s = Source(
        id: 'c1',
        kind: SourceKind.book,
        authors: [kalala],
        year: '2019',
        title: 'Économie congolaise',
        chapterTitle: 'Le secteur informel',
        editors: [mbuyi, ilunga],
        pages: '45-67',
        publisher: 'L\'Harmattan',
      );
      expect(Apa.reference(s).markdown,
          'Kalala, P. M. (2019). Le secteur informel. Dans J.-P. Mbuyi et M. Ilunga (dir.), '
          '*Économie congolaise* (p. 45–67). L\'Harmattan.');
    });

    test('article : revue et volume en italique, numéro, pages, DOI', () {
      const s = Source(
        id: 'a1',
        kind: SourceKind.article,
        authors: [mbuyi, kalala],
        year: '2021',
        title: 'Microfinance et inclusion financière en RDC',
        journal: 'Revue congolaise de gestion',
        volume: '12',
        issue: '3',
        pages: '101-120',
        doi: '10.1234/rcg.2021.003',
      );
      expect(Apa.reference(s).markdown,
          'Mbuyi, J.-P. et Kalala, P. M. (2021). Microfinance et inclusion financière en RDC. '
          '*Revue congolaise de gestion*, *12*(3), 101–120. https://doi.org/10.1234/rcg.2021.003');
    });

    test('mémoire : type et établissement entre crochets', () {
      const s = Source(
        id: 't1',
        kind: SourceKind.thesis,
        authors: [ilunga],
        year: '2020',
        title: 'Le crédit bancaire aux PME',
        degree: 'Mémoire de licence',
        institution: 'Université de Kinshasa',
      );
      expect(Apa.reference(s).markdown,
          'Ilunga, M. (2020). *Le crédit bancaire aux PME* [Mémoire de licence, Université de Kinshasa].');
    });

    test('site web d\'une organisation : date de consultation', () {
      final s = Source(
        id: 'w1',
        kind: SourceKind.website,
        organization: 'Banque centrale du Congo',
        siteName: 'Banque centrale du Congo',
        publishedDate: DateTime(2024, 3, 12),
        title: 'Rapport annuel 2023',
        url: 'https://www.bcc.cd/rapport-2023',
        accessedDate: DateTime(2026, 10, 1),
      );
      expect(Apa.reference(s).markdown,
          'Banque centrale du Congo. (2024, 12 mars). *Rapport annuel 2023*. '
          'Consulté le 1er octobre 2026, à l\'adresse https://www.bcc.cd/rapport-2023');
    });

    test('texte légal : Journal officiel en italique', () {
      const s = Source(
        id: 'l1',
        kind: SourceKind.legalText,
        year: '2018',
        title: 'Loi n° 18/035 du 13 décembre 2018 fixant les principes fondamentaux relatifs à '
            'l\'organisation de la santé publique',
        journal: 'Journal officiel de la République démocratique du Congo',
        issue: 'spécial',
      );
      expect(Apa.reference(s).markdown,
          'Loi n° 18/035 du 13 décembre 2018 fixant les principes fondamentaux relatifs à l\'organisation '
          'de la santé publique. (2018). *Journal officiel de la République démocratique du Congo*, n° spécial.');
    });

    test('titre finissant par « ? » : pas de point ajouté', () {
      const s = Source(id: 'q', kind: SourceKind.book, authors: [mbuyi], year: '2010',
          title: 'Faut-il réformer l\'impôt ?', publisher: 'PUK');
      expect(Apa.reference(s).plain, 'Mbuyi, J.-P. (2010). Faut-il réformer l\'impôt ? PUK.');
    });

    test('citation dans le texte', () {
      expect(Apa.inText(book(), locator: '45'), '(Mbuyi, 2015, p. 45)');
      expect(Apa.inText(book(authors: const [mbuyi, kalala])), '(Mbuyi et Kalala, 2015)');
      expect(Apa.inText(book(authors: const [mbuyi, kalala, ilunga])), '(Mbuyi et al., 2015)');
    });
  });

  group('notes de bas de page', () {
    test('première citation d\'un ouvrage : prénom NOM, lieu, éditeur, année, page', () {
      expect(Footnote.full(book(), locator: '45').markdown,
          'Jean-Pierre MBUYI, *La gestion financière des PME : cas de Kinshasa*, Kinshasa, '
          'Presses universitaires de Kinshasa, 2015, p. 45.');
    });

    test('lieu, éditeur ou date absents : s.l., s.é., s.d.', () {
      const s = Source(id: 'x', kind: SourceKind.book, authors: [mbuyi], title: 'Titre');
      expect(Footnote.full(s).plain, 'Jean-Pierre MBUYI, Titre, s.l., s.é., s.d.');
    });

    test('article : titre entre guillemets, revue en italique', () {
      const s = Source(id: 'a', kind: SourceKind.article, authors: [mbuyi], year: '2021', title: 'Microfinance',
          journal: 'Revue congolaise de gestion', volume: '12', issue: '3', pages: '101-120');
      expect(Footnote.full(s, locator: '105').markdown,
          'Jean-Pierre MBUYI, « Microfinance », *Revue congolaise de gestion*, vol. 12, n° 3, 2021, p. 105.');
      expect(Footnote.full(s).plain, endsWith('2021, pp. 101–120.'));
    });

    test('plus de trois auteurs : et al.', () {
      final s = book(authors: const [mbuyi, kalala, ilunga, Person(last: 'Tshibanda', first: 'Luc')]);
      expect(Footnote.authors(s), 'Jean-Pierre MBUYI et al.');
    });

    test('pages et articles de loi', () {
      expect(Footnote.locator('45'), 'p. 45');
      expect(Footnote.locator('45-47'), 'pp. 45–47');
      expect(Footnote.locator('art. 12'), 'art. 12');
    });

    test('suite de notes : complète, Ibid., Ibid. même page, op. cit., op. cit. avec titre', () {
      final b1 = book();
      const b2 = Source(id: 'b2', kind: SourceKind.book, authors: [mbuyi], year: '2018', title: 'Fiscalité',
          publisher: 'PUK', place: 'Kinshasa');
      const t1 = Source(id: 't1', kind: SourceKind.thesis, authors: [ilunga], year: '2020', title: 'Le crédit',
          degree: 'Mémoire de licence', institution: 'UNIKIN');
      final notes = FootnoteSequencer.notes(
        const [
          Citation('b1', locator: '45'),
          Citation('b1', locator: '47'),
          Citation('b1', locator: '47'),
          Citation('t1', locator: '3'),
          Citation('b1', locator: '50'),
          Citation('b2', locator: '9'),
          Citation('t1', locator: '8'),
          Citation('inconnue'),
        ],
        {'b1': b1, 'b2': b2, 't1': t1},
      ).map((n) => n.markdown).toList();

      expect(notes, hasLength(7));
      expect(notes[0], startsWith('Jean-Pierre MBUYI, *La gestion financière'));
      expect(notes[1], '*Ibid.*, p. 47.');
      expect(notes[2], '*Ibid.*');
      expect(notes[3], 'Marie ILUNGA, *Le crédit*, Mémoire de licence, UNIKIN, 2020, p. 3.');
      // Mbuyi a deux ouvrages cités : le titre est rappelé.
      expect(notes[4], 'Jean-Pierre MBUYI, *La gestion financière des PME*, *op. cit.*, p. 50.');
      expect(notes[5], startsWith('Jean-Pierre MBUYI, *Fiscalité*, Kinshasa, PUK, 2018, p. 9.'));
      expect(notes[6], 'Marie ILUNGA, *op. cit.*, p. 8.');
    });
  });

  group('tri', () {
    final sources = [
      const Source(id: '1', kind: SourceKind.website, organization: 'Banque centrale du Congo', title: 'Rapport',
          url: 'https://bcc.cd'),
      const Source(id: '2', kind: SourceKind.book, authors: [Person(last: 'Élongo', first: 'A')], year: '2010',
          title: 'Z', publisher: 'P'),
      const Source(id: '3', kind: SourceKind.book, authors: [mbuyi], year: '2018', title: 'B', publisher: 'P'),
      const Source(id: '4', kind: SourceKind.book, authors: [mbuyi], year: '2015', title: 'A', publisher: 'P'),
      const Source(id: '5', kind: SourceKind.article, authors: [Person(last: 'akilimali', first: 'R')],
          year: '2001', title: 'Art', journal: 'J'),
    ];

    test('alphabétique : accents et majuscules ignorés, puis année', () {
      expect(BibliographySorter.alphabetical(sources).map((s) => s.id), ['5', '1', '2', '4', '3']);
    });

    test('par rubriques, dans l\'ordre habituel', () {
      final sections = BibliographySorter.sections(sources, BibliographyOrder.byKind);
      expect(sections.map((s) => s.title), ['Ouvrages', 'Articles', 'Webographie']);
      expect(sections.first.sources.map((s) => s.id), ['2', '4', '3']);
      final text = BibliographySorter.asText(sources, BibliographyOrder.byKind);
      expect(text, startsWith('I. OUVRAGES\nÉlongo, A. (2010).'));
      expect(text, contains('\n\nIII. WEBOGRAPHIE\nBanque centrale du Congo.'));
    });
  });

  test('validation par type de source', () {
    expect(const Source(id: 'x', kind: SourceKind.book, title: '').validate().keys, containsAll(['title', 'publisher']));
    expect(const Source(id: 'x', kind: SourceKind.article, title: 'T', year: '21').validate().keys,
        containsAll(['journal', 'year']));
    expect(const Source(id: 'x', kind: SourceKind.website, title: 'T', url: 'www.x.cd').validate()['url'],
        contains('http'));
    expect(const Source(id: 'x', kind: SourceKind.legalText, title: 'Loi', year: '2018').validate(), isEmpty);
  });

  test('aller-retour JSON (champs vides retirés)', () {
    final s = book(edition: '2');
    final json = s.toJson();
    expect(json.containsKey('doi'), isFalse);
    final back = Source.fromJson('b1', SourceKind.book, json);
    expect(Apa.reference(back).markdown, Apa.reference(s).markdown);
  });
}

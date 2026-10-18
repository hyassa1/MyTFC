import 'package:intl/intl.dart';

import 'source.dart';
import 'styled_text.dart';

/// Date en toutes lettres : « 12 mars 2024 », « 1er octobre 2026 ».
String frenchDate(DateTime d, {bool withYear = true}) {
  final rest = DateFormat(withYear ? 'MMMM y' : 'MMMM', 'fr').format(d);
  return '${d.day == 1 ? '1er' : d.day} $rest';
}

/// Références au format APA 7e édition (adaptation française : « et »
/// entre les deux derniers auteurs, « s.d. », « éd. », « dir. »).
abstract final class Apa {
  static String _title(Source s) =>
      s.subtitle == null ? s.title.trim() : '${s.title.trim()} : ${s.subtitle!.trim()}';

  /// « Mbuyi, J.-P. » ; un nom sans prénom reste tel quel.
  static String _person(Person p) => p.initials.isEmpty ? p.last : '${p.last}, ${p.initials}';

  /// Liste d'auteurs APA : jusqu'à 20 noms ; au-delà, les 19 premiers, « … », le dernier.
  static String authorList(List<Person> authors) {
    final names = authors.map(_person).toList();
    if (names.length == 1) return names.first;
    if (names.length > 20) {
      return '${names.take(19).join(', ')}, . . . ${names.last}';
    }
    return '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
  }

  /// Directeurs dans « Dans J. Mbuyi (dir.), … » : initiales avant le nom.
  static String _editors(List<Person> editors) {
    final names = editors.map((p) => p.initials.isEmpty ? p.last : '${p.initials} ${p.last}').toList();
    final joined = names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
    return '$joined (dir.)';
  }

  static String _edition(String? edition) {
    final e = edition?.trim();
    if (e == null || e.isEmpty || e == '1') return '';
    return RegExp(r'^\d+$').hasMatch(e) ? '${e}e éd.' : e;
  }

  static String _date(Source s) {
    final year = s.year ?? s.publishedDate?.year.toString();
    if (year == null) return 's.d.';
    if (s.kind == SourceKind.website && s.publishedDate != null) {
      return '$year, ${frenchDate(s.publishedDate!, withYear: false)}';
    }
    return year;
  }

  static String? _link(Source s) {
    final doi = s.doi?.trim();
    if (doi != null && doi.isNotEmpty) {
      return doi.startsWith('http') ? doi : 'https://doi.org/${doi.replaceFirst(RegExp('^doi:', caseSensitive: false), '')}';
    }
    return s.url?.trim();
  }

  /// Référence complète, pour la bibliographie.
  static StyledText reference(Source s) {
    final b = StyledBuilder();
    final titleItalic = s.kind != SourceKind.article && s.kind != SourceKind.legalText && !s.isChapter;
    final mainTitle = s.isChapter ? s.chapterTitle!.trim() : _title(s);

    // 1. Auteur (ou, à défaut, le titre prend sa place).
    var titleUsedAsAuthor = false;
    if (s.organization != null) {
      b.add(s.organization!.trim());
      b.period();
    } else if (s.authors.isNotEmpty) {
      b.add(authorList(s.authors));
      b.period();
    } else {
      titleUsedAsAuthor = true;
      b.add(mainTitle, italic: titleItalic);
      if (s.kind == SourceKind.book && !s.isChapter && _edition(s.edition).isNotEmpty) {
        b.add(' (${_edition(s.edition)})');
      }
      b.period();
    }

    // 2. Date.
    b.add(' (${_date(s)}).');

    // 3. Titre et 4. source.
    void title() {
      if (titleUsedAsAuthor) return;
      b.add(' ');
      b.add(mainTitle, italic: titleItalic);
    }

    switch (s.kind) {
      case SourceKind.book when s.isChapter:
        title();
        b.period();
        b.add(' Dans ');
        if (s.editors.isNotEmpty) b.add('${_editors(s.editors)}, ');
        b.italic(_title(s));
        final details = [
          if (_edition(s.edition).isNotEmpty) _edition(s.edition),
          if (s.pages != null) 'p. ${pageRange(s.pages!)}',
        ];
        if (details.isNotEmpty) b.add(' (${details.join(', ')})');
        b.period();
        if (s.publisher != null) {
          b.add(' ${s.publisher!.trim()}');
          b.period();
        }
      case SourceKind.book:
        title();
        if (!titleUsedAsAuthor && _edition(s.edition).isNotEmpty) b.add(' (${_edition(s.edition)})');
        b.period();
        if (s.publisher != null) {
          b.add(' ${s.publisher!.trim()}');
          b.period();
        }
      case SourceKind.article:
        title();
        b.period();
        if (s.journal != null) {
          b.add(' ');
          b.italic(s.journal!.trim());
        }
        if (s.volume != null) {
          b.add(', ');
          b.italic(s.volume!.trim());
        }
        if (s.issue != null) b.add(s.volume != null ? '(${s.issue!.trim()})' : ', (${s.issue!.trim()})');
        if (s.pages != null) b.add(', ${pageRange(s.pages!)}');
        b.period();
      case SourceKind.thesis:
        title();
        final bracket = [s.degree?.trim(), s.institution?.trim()].whereType<String>().join(', ');
        if (bracket.isNotEmpty) b.add(' [$bracket]');
        b.period();
      case SourceKind.website:
        title();
        b.period();
        final site = s.siteName?.trim();
        if (site != null && site.isNotEmpty && site != s.organization?.trim()) {
          b.add(' $site');
          b.period();
        }
      case SourceKind.legalText:
        title();
        b.period();
        if (s.journal != null) {
          b.add(' ');
          b.italic(s.journal!.trim());
          if (s.issue != null) b.add(', n° ${s.issue!.trim()}');
          if (s.pages != null) b.add(', p. ${pageRange(s.pages!)}');
          b.period();
        }
    }

    // 5. Lien (DOI ou URL), sans point final.
    final link = _link(s);
    if (link != null && link.isNotEmpty) {
      if (s.kind == SourceKind.website && s.accessedDate != null) {
        b.add(' Consulté le ${frenchDate(s.accessedDate!)}, à l\'adresse $link');
      } else {
        b.add(' $link');
      }
    }
    return b.build();
  }

  /// Citation dans le texte : (Mbuyi, 2015, p. 45) ; (Mbuyi et Kalala, 2015) ;
  /// (Mbuyi et al., 2015) à partir de trois auteurs.
  static String inText(Source s, {String? locator}) {
    final String who;
    if (s.organization != null) {
      who = s.organization!.trim();
    } else if (s.authors.isEmpty) {
      final t = s.isChapter ? s.chapterTitle! : s.title;
      who = t.length > 40 ? '${t.substring(0, 40).trimRight()}…' : t;
    } else if (s.authors.length == 1) {
      who = s.authors.first.last;
    } else if (s.authors.length == 2) {
      who = '${s.authors[0].last} et ${s.authors[1].last}';
    } else {
      who = '${s.authors.first.last} et al.';
    }
    final loc = locator == null || locator.trim().isEmpty ? '' : ', ${Footnote.locator(locator)}';
    return '($who, ${_date(s).split(',').first}$loc)';
  }
}

/// Notes de bas de page « à la française », très utilisées dans les
/// établissements congolais : référence complète à la première citation,
/// puis « Ibid. » (même source que la note précédente) ou « op. cit. ».
abstract final class Footnote {
  /// « 45 » → « p. 45 » ; « 45-47 » → « pp. 45–47 » ; « art. 12 » reste tel quel.
  static String locator(String raw) {
    final v = raw.trim();
    if (RegExp(r'^\d+$').hasMatch(v)) return 'p. $v';
    if (RegExp(r'^\d+\s*[-–]\s*\d+$').hasMatch(v)) return 'pp. ${pageRange(v)}';
    return v;
  }

  /// « Jean MBUYI » ; au-delà de trois auteurs : « Jean MBUYI et al. ».
  static String authors(Source s) {
    if (s.organization != null) return s.organization!.trim().toUpperCase();
    String name(Person p) => [p.first, p.last.toUpperCase()].where((x) => x.isNotEmpty).join(' ');
    final a = s.authors;
    if (a.isEmpty) return '';
    if (a.length > 3) return '${name(a.first)} et al.';
    if (a.length == 1) return name(a.first);
    return '${a.sublist(0, a.length - 1).map(name).join(', ')} et ${name(a.last)}';
  }

  static String _title(Source s) =>
      s.subtitle == null ? s.title.trim() : '${s.title.trim()} : ${s.subtitle!.trim()}';

  /// Première citation : référence complète.
  static StyledText full(Source s, {String? locator}) {
    final b = StyledBuilder();
    final who = authors(s);
    final parts = <void Function()>[];
    void text(String t) => parts.add(() => b.add(t));
    void ital(String t) => parts.add(() => b.italic(t));
    String? v(String? x) => x?.trim().isEmpty ?? true ? null : x!.trim();

    if (who.isNotEmpty) text(who);
    switch (s.kind) {
      case SourceKind.book:
        if (s.isChapter) {
          text('« ${s.chapterTitle!.trim()} »');
          final eds = s.editors.isEmpty ? '' : '${s.editors.map((p) => [p.first, p.last.toUpperCase()].where((x) => x.isNotEmpty).join(' ')).join(' et ')} (dir.), ';
          parts.add(() {
            b.add('in $eds');
            b.italic(_title(s));
          });
        } else {
          ital(_title(s));
        }
        final ed = v(s.edition);
        if (ed != null && ed != '1') text(RegExp(r'^\d+$').hasMatch(ed) ? '${ed}e éd.' : ed);
        text(v(s.place) ?? 's.l.');
        text(v(s.publisher) ?? 's.é.');
        text(v(s.year) ?? 's.d.');
      case SourceKind.article:
        text('« ${_title(s)} »');
        if (v(s.journal) != null) ital(s.journal!.trim());
        if (v(s.volume) != null) text('vol. ${s.volume!.trim()}');
        if (v(s.issue) != null) text('n° ${s.issue!.trim()}');
        text(v(s.year) ?? 's.d.');
        if (locator == null && v(s.pages) != null) text('pp. ${pageRange(s.pages!)}');
      case SourceKind.thesis:
        ital(_title(s));
        if (v(s.degree) != null) text(s.degree!.trim());
        if (v(s.institution) != null) text(s.institution!.trim());
        text(v(s.year) ?? 's.d.');
      case SourceKind.website:
        text('« ${_title(s)} »');
        if (v(s.siteName) != null && s.siteName!.trim() != s.organization?.trim()) ital(s.siteName!.trim());
        if (v(s.year) != null) text(s.year!);
        if (v(s.url) != null) {
          final consulted = s.accessedDate == null
              ? ''
              : ' (consulté le ${frenchDate(s.accessedDate!)})';
          text('disponible sur ${s.url!.trim()}$consulted');
        }
      case SourceKind.legalText:
        text(_title(s));
        if (v(s.journal) != null) ital(s.journal!.trim());
        if (v(s.issue) != null) text('n° ${s.issue!.trim()}');
        if (v(s.year) != null) text(s.year!);
    }
    if (locator != null && locator.trim().isNotEmpty) text(Footnote.locator(locator));

    for (var i = 0; i < parts.length; i++) {
      if (i > 0) b.add(', ');
      parts[i]();
    }
    b.period();
    return b.build();
  }

  /// Citation suivante (non consécutive) : « Jean MBUYI, op. cit., p. 50. ».
  /// [withTitle] : l'auteur a plusieurs sources citées, on précise le titre.
  static StyledText short(Source s, {String? locator, bool withTitle = false}) {
    final b = StyledBuilder();
    final who = authors(s);
    if (who.isNotEmpty) {
      b.add('$who, ');
    }
    if (withTitle || who.isEmpty) {
      if (s.kind == SourceKind.article || s.kind == SourceKind.website || s.isChapter) {
        b.add('« ${s.isChapter ? s.chapterTitle!.trim() : s.title.trim()} », ');
      } else {
        b.italic(s.title.trim());
        b.add(', ');
      }
    }
    b.italic('op. cit.');
    if (locator != null && locator.trim().isNotEmpty) b.add(', ${Footnote.locator(locator)}');
    b.period();
    return b.build();
  }

  /// Même source que la note précédente : « Ibid., p. 47. » ; même page : « Ibid. ».
  static StyledText ibid({String? locator}) {
    final b = StyledBuilder()..italic('Ibid.');
    if (locator != null && locator.trim().isNotEmpty) {
      b.add(', ${Footnote.locator(locator)}');
      b.period();
    }
    return b.build();
  }
}

/// Une citation dans le texte de l'étudiant, dans l'ordre d'apparition.
class Citation {
  const Citation(this.sourceId, {this.locator});
  final String sourceId;

  /// Page(s) ou article cités : « 45 », « 45-47 », « art. 12 ».
  final String? locator;
}

/// Numérote les notes d'un chapitre et choisit la bonne forme pour chacune.
abstract final class FootnoteSequencer {
  static List<StyledText> notes(List<Citation> citations, Map<String, Source> sources) {
    final seen = <String>{};
    // Auteurs (forme note) qui ont plusieurs sources citées : op. cit. avec titre.
    final byAuthor = <String, Set<String>>{};
    for (final c in citations) {
      final s = sources[c.sourceId];
      if (s != null) (byAuthor[Footnote.authors(s)] ??= {}).add(s.id);
    }

    final out = <StyledText>[];
    Citation? previous;
    for (final c in citations) {
      final s = sources[c.sourceId];
      if (s == null) continue;
      if (previous != null && previous.sourceId == c.sourceId) {
        final samePlace = (previous.locator ?? '').trim() == (c.locator ?? '').trim();
        out.add(Footnote.ibid(locator: samePlace ? null : c.locator));
      } else if (seen.contains(c.sourceId)) {
        out.add(Footnote.short(s, locator: c.locator, withTitle: (byAuthor[Footnote.authors(s)]?.length ?? 0) > 1));
      } else {
        out.add(Footnote.full(s, locator: c.locator));
      }
      seen.add(c.sourceId);
      previous = c;
    }
    return out;
  }
}

/// Classement de la bibliographie.
enum BibliographyOrder {
  /// Ordre alphabétique des auteurs (APA).
  alphabetical,

  /// Par rubriques (ouvrages, articles, mémoires, textes légaux, webographie),
  /// puis alphabétique dans chaque rubrique.
  byKind,
}

class BibliographySection {
  const BibliographySection(this.title, this.sources);

  /// null en ordre alphabétique simple.
  final String? title;
  final List<Source> sources;
}

abstract final class BibliographySorter {
  static const kindOrder = [
    SourceKind.book,
    SourceKind.article,
    SourceKind.thesis,
    SourceKind.legalText,
    SourceKind.website,
  ];

  /// Clé APA : premier auteur (ou organisation, ou titre), puis année, puis titre.
  static String sortKey(Source s) {
    final lead = s.organization ??
        (s.authors.isNotEmpty ? '${s.authors.first.last} ${s.authors.first.first}' : s.title);
    final others = s.authors.skip(1).map((a) => a.last).join(' ');
    return '${foldForSort(lead)}\u0000${foldForSort(others)}\u0000${s.year ?? '9999'}\u0000${foldForSort(s.title)}';
  }

  static List<Source> alphabetical(Iterable<Source> sources) =>
      sources.toList()..sort((a, b) => sortKey(a).compareTo(sortKey(b)));

  static List<BibliographySection> sections(Iterable<Source> sources, BibliographyOrder order) {
    if (order == BibliographyOrder.alphabetical) return [BibliographySection(null, alphabetical(sources))];
    return [
      for (final kind in kindOrder)
        if (sources.where((s) => s.kind == kind).toList() case final list when list.isNotEmpty)
          BibliographySection(kind.groupTitle, alphabetical(list)),
    ];
  }

  /// Texte brut de la bibliographie, prêt à coller dans le travail.
  static String asText(Iterable<Source> sources, BibliographyOrder order) {
    final buf = StringBuffer();
    final roman = ['I', 'II', 'III', 'IV', 'V'];
    final secs = sections(sources, order);
    for (var i = 0; i < secs.length; i++) {
      final sec = secs[i];
      if (sec.title != null) {
        if (i > 0) buf.writeln();
        buf.writeln('${roman[i]}. ${sec.title!.toUpperCase()}');
      }
      for (final s in sec.sources) {
        buf.writeln(Apa.reference(s).plain);
      }
    }
    return buf.toString().trimRight();
  }
}

/// Type de source (miroir de l'enum SQL `public.source_kind`).
enum SourceKind {
  book('book', 'Ouvrage', 'Ouvrages'),
  article('article', 'Article de revue', 'Articles'),
  thesis('thesis', 'Mémoire, TFC ou thèse', 'Mémoires et thèses'),
  website('website', 'Site web', 'Webographie'),
  legalText('legal_text', 'Texte légal', 'Textes légaux et réglementaires');

  const SourceKind(this.code, this.label, this.groupTitle);

  final String code;
  final String label;

  /// Titre de rubrique quand la bibliographie est classée par type
  /// (présentation courante dans les établissements congolais).
  final String groupTitle;

  static SourceKind fromCode(String? code) => values.where((v) => v.code == code).firstOrNull ?? book;
}

/// Auteur ou directeur d'ouvrage.
class Person {
  const Person({required this.last, this.first = ''});

  final String last;

  /// Prénom(s), éventuellement post-nom. Ex. « Jean-Pierre ».
  final String first;

  factory Person.fromJson(Map<String, dynamic> j) =>
      Person(last: (j['last'] as String? ?? '').trim(), first: (j['first'] as String? ?? '').trim());

  Map<String, dynamic> toJson() => {'last': last, 'first': first};

  bool get isEmpty => last.trim().isEmpty;

  /// Initiales APA : « Jean-Pierre Marie » → « J.-P. M. ».
  String get initials => first
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.split('-').where((p) => p.isNotEmpty).map((p) => '${p.characters1}.').join('-'))
      .join(' ');
}

extension on String {
  /// Première lettre (gère les lettres accentuées composées).
  String get characters1 => isEmpty ? '' : substring(0, 1).toUpperCase();
}

/// Source bibliographique saisie par l'étudiant (colonne `data` de
/// `bibliography_entries`). Tous les champs sont du texte libre : l'étudiant
/// recopie ce qui figure sur la source.
class Source {
  const Source({
    required this.id,
    required this.kind,
    this.authors = const [],
    this.organization,
    this.year,
    this.title = '',
    this.subtitle,
    this.edition,
    this.publisher,
    this.place,
    this.chapterTitle,
    this.editors = const [],
    this.pages,
    this.journal,
    this.volume,
    this.issue,
    this.doi,
    this.url,
    this.degree,
    this.institution,
    this.siteName,
    this.publishedDate,
    this.accessedDate,
    this.workId,
  });

  final String id;
  final SourceKind kind;
  final List<Person> authors;

  /// Auteur collectif (ministère, Banque centrale du Congo…), à la place des personnes.
  final String? organization;

  /// Année ; vide = « s.d. » (sans date).
  final String? year;
  final String title;
  final String? subtitle;

  /// Numéro d'édition (« 2 » pour la 2e édition) ; vide = première édition.
  final String? edition;
  final String? publisher;

  /// Ville d'édition (notes de bas de page ; APA 7 ne l'utilise plus).
  final String? place;

  /// Chapitre dans un ouvrage collectif : titre du chapitre, directeurs, pages.
  final String? chapterTitle;
  final List<Person> editors;

  /// Pages d'un article ou d'un chapitre, ex. « 45-67 ».
  final String? pages;

  /// Revue (article) ou Journal officiel (texte légal).
  final String? journal;
  final String? volume;

  /// Numéro de la revue ou du Journal officiel.
  final String? issue;
  final String? doi;
  final String? url;

  /// Mémoire : « Mémoire de licence », « TFC », « Thèse de doctorat ».
  final String? degree;
  final String? institution;
  final String? siteName;
  final DateTime? publishedDate;
  final DateTime? accessedDate;
  final String? workId;

  bool get isChapter => kind == SourceKind.book && (chapterTitle?.trim().isNotEmpty ?? false);

  bool get hasAuthor => (organization?.trim().isNotEmpty ?? false) || authors.any((a) => !a.isEmpty);

  factory Source.fromJson(String id, SourceKind kind, Map<String, dynamic> j, {String? workId}) {
    String? s(String k) {
      final v = j[k]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    List<Person> people(String k) => [
          for (final p in (j[k] as List?) ?? const [])
            if (p is Map) Person.fromJson(Map<String, dynamic>.from(p)),
        ].where((p) => !p.isEmpty).toList();

    return Source(
      id: id,
      kind: kind,
      workId: workId,
      authors: people('authors'),
      organization: s('organization'),
      year: s('year'),
      title: s('title') ?? '',
      subtitle: s('subtitle'),
      edition: s('edition'),
      publisher: s('publisher'),
      place: s('place'),
      chapterTitle: s('chapter_title'),
      editors: people('editors'),
      pages: s('pages'),
      journal: s('journal'),
      volume: s('volume'),
      issue: s('issue'),
      doi: s('doi'),
      url: s('url'),
      degree: s('degree'),
      institution: s('institution'),
      siteName: s('site_name'),
      publishedDate: DateTime.tryParse(s('published_date') ?? ''),
      accessedDate: DateTime.tryParse(s('accessed_date') ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    String? d(DateTime? v) => v == null ? null : '${v.year.toString().padLeft(4, '0')}-'
        '${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    final map = <String, dynamic>{
      'authors': [for (final a in authors) a.toJson()],
      'organization': organization,
      'year': year,
      'title': title,
      'subtitle': subtitle,
      'edition': edition,
      'publisher': publisher,
      'place': place,
      'chapter_title': chapterTitle,
      'editors': [for (final e in editors) e.toJson()],
      'pages': pages,
      'journal': journal,
      'volume': volume,
      'issue': issue,
      'doi': doi,
      'url': url,
      'degree': degree,
      'institution': institution,
      'site_name': siteName,
      'published_date': d(publishedDate),
      'accessed_date': d(accessedDate),
    };
    map.removeWhere((_, v) => v == null || (v is List && v.isEmpty));
    return map;
  }

  /// Champs obligatoires selon le type (messages par clé de champ).
  Map<String, String> validate() {
    final e = <String, String>{};
    bool empty(String? v) => v == null || v.trim().isEmpty;
    if (title.trim().isEmpty) e['title'] = 'Le titre est obligatoire.';
    if (year != null && !RegExp(r'^\d{4}[a-z]?$').hasMatch(year!)) e['year'] = 'Année sur 4 chiffres, ex. 2021.';
    switch (kind) {
      case SourceKind.book:
        if (empty(publisher)) e['publisher'] = 'Indique l\'éditeur.';
        if (isChapter && editors.isEmpty) e['editors'] = 'Indique le ou les directeurs de l\'ouvrage.';
      case SourceKind.article:
        if (empty(journal)) e['journal'] = 'Indique le nom de la revue.';
      case SourceKind.thesis:
        if (empty(degree)) e['degree'] = 'Précise le type de travail (ex. mémoire de licence).';
        if (empty(institution)) e['institution'] = 'Indique l\'établissement.';
      case SourceKind.website:
        if (empty(url)) e['url'] = 'Indique l\'adresse de la page.';
      case SourceKind.legalText:
        break;
    }
    if (!empty(url) && !RegExp(r'^https?://\S+$').hasMatch(url!.trim())) {
      e['url'] = 'L\'adresse doit commencer par http:// ou https://';
    }
    return e;
  }
}

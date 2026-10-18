/// Texte avec passages en italique (titres, revues, locutions latines),
/// rendu par l'écran, le PDF et le Word.
class StyledRun {
  const StyledRun(this.text, {this.italic = false});
  final String text;
  final bool italic;

  @override
  bool operator ==(Object other) => other is StyledRun && other.text == text && other.italic == italic;

  @override
  int get hashCode => Object.hash(text, italic);

  @override
  String toString() => italic ? '*$text*' : text;
}

class StyledText {
  const StyledText(this.runs);

  final List<StyledRun> runs;

  String get plain => runs.map((r) => r.text).join();

  /// Forme lisible pour les tests et le presse-papiers riche : *italique*.
  String get markdown => runs.map((r) => r.toString()).join();

  @override
  String toString() => plain;
}

/// Construction pas à pas d'un [StyledText], avec la ponctuation française.
class StyledBuilder {
  final _runs = <StyledRun>[];

  void add(String text, {bool italic = false}) {
    if (text.isEmpty) return;
    if (_runs.isNotEmpty && _runs.last.italic == italic) {
      _runs[_runs.length - 1] = StyledRun(_runs.last.text + text, italic: italic);
    } else {
      _runs.add(StyledRun(text, italic: italic));
    }
  }

  void italic(String text) => add(text, italic: true);

  String get _plain => _runs.map((r) => r.text).join();

  /// Termine la phrase par un point, sauf si elle finit déjà par . ? ou !
  void period() {
    final t = _plain.trimRight();
    if (t.isEmpty || t.endsWith('.') || t.endsWith('?') || t.endsWith('!')) return;
    add('.');
  }

  bool get isEmpty => _runs.isEmpty;

  StyledText build() {
    // Espaces superflus (champs vides) supprimés.
    final cleaned = <StyledRun>[];
    for (final r in _runs) {
      final text = r.text.replaceAll(RegExp(r' {2,}'), ' ');
      if (text.isNotEmpty) cleaned.add(StyledRun(text, italic: r.italic));
    }
    return StyledText(cleaned);
  }
}

/// « 45-67 » → « 45–67 » (tiret demi-cadratin des intervalles).
String pageRange(String pages) => pages.trim().replaceAll(RegExp(r'\s*[-–—]\s*'), '–');

/// Retire les accents pour le tri alphabétique (« Élise » avec les E).
String foldForSort(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸŒÆ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoaAAAAAACEEEEIIIINOOOOOUUUUYYOA';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString().toLowerCase().trim();
}

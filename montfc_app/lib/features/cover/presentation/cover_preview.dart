import 'package:flutter/material.dart';

import '../domain/cover_layout.dart';

/// Aperçu fidèle d'une page de garde : la page A4 est dessinée à l'échelle
/// (1 point typographique = 1 unité logique) puis réduite à la largeur de
/// l'écran. Le PDF et le Word utilisent les mêmes dimensions.
class CoverPreview extends StatelessWidget {
  const CoverPreview({super.key, required this.layout, required this.blocks});

  final CoverLayout layout;

  /// Blocs déjà résolus (CoverLayout.resolve).
  final List<CoverBlock> blocks;

  static const _ink = Color(0xFF111111);

  @override
  Widget build(BuildContext context) {
    final page = layout.page;
    final m = page.margins;
    final width = page.widthCm * pointsPerCm;
    final height = page.heightCm * pointsPerCm;
    final contentWidth = (page.widthCm - m.left - m.right) * pointsPerCm;

    // Un texte trop long ne déborde pas de la feuille dans l'aperçu.
    Widget content = ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final b in blocks) _block(b, contentWidth)],
        ),
      ),
    );
    // Cadre de page : tracé sur les marges, le texte est en retrait de 0,3 cm.
    if (page.border != CoverBorder.none) {
      content = _framed(content, page.border, 0.3 * pointsPerCm);
    }

    return AspectRatio(
      aspectRatio: width / height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(blurRadius: 6, color: Color(0x33000000), offset: Offset(0, 2))],
        ),
        child: FittedBox(
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  m.left * pointsPerCm, m.top * pointsPerCm, m.right * pointsPerCm, m.bottom * pointsPerCm),
              // Un texte trop long ne déborde pas de la feuille dans l'aperçu.
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _framed(Widget child, CoverBorder border, double padding) {
    final inner = Container(
      decoration: BoxDecoration(border: Border.all(color: _ink)),
      padding: EdgeInsets.all(padding),
      child: child,
    );
    if (border == CoverBorder.single) return SizedBox.expand(child: inner);
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: _ink, width: 2)),
        padding: const EdgeInsets.all(2),
        child: inner,
      ),
    );
  }

  Widget _block(CoverBlock b, double contentWidth) => switch (b) {
        TextBlock() => Padding(
            padding: EdgeInsets.only(
              top: b.spaceBeforePt,
              bottom: b.spaceAfterPt,
              left: contentWidth * b.indentLeftRatio,
            ),
            child: Text(
              b.text,
              textAlign: switch (b.align) {
                CoverAlign.left => TextAlign.left,
                CoverAlign.center => TextAlign.center,
                CoverAlign.right => TextAlign.right,
                CoverAlign.justify => TextAlign.justify,
              },
              style: TextStyle(
                // Police à empattement proche de Times New Roman.
                fontFamily: 'LiberationSerif',
                fontFamilyFallback: const ['serif'],
                color: _ink,
                fontSize: b.size ?? layout.fontSize,
                height: 1.25,
                fontWeight: b.bold ? FontWeight.bold : FontWeight.normal,
                fontStyle: b.italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        SpacerBlock() => SizedBox(height: b.heightCm * pointsPerCm),
        RuleBlock() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(height: b.thicknessPt, color: _ink),
          ),
        BoxBlock() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _ink, width: b.border == CoverBorder.double ? 2.5 : 1),
              ),
              padding: EdgeInsets.all(b.paddingCm * pointsPerCm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final c in b.blocks) _block(c, contentWidth - 2 * b.paddingCm * pointsPerCm)],
              ),
            ),
          ),
      };
}

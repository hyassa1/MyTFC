import 'package:flutter/material.dart';

import '../domain/styled_text.dart';

/// Affiche un [StyledText] (italiques des titres et revues).
class StyledTextView extends StatelessWidget {
  const StyledTextView(this.text, {super.key, this.style});

  final StyledText text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          for (final r in text.runs)
            TextSpan(text: r.text, style: r.italic ? const TextStyle(fontStyle: FontStyle.italic) : null),
        ]),
        style: style,
      );
}

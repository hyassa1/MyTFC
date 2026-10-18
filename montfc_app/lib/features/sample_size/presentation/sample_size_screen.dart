import 'package:flutter/material.dart';

import '../domain/sample_size.dart';

/// Calculateur de taille d'échantillon (gratuit, hors ligne).
class SampleSizeScreen extends StatelessWidget {
  const SampleSizeScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Taille de l\'échantillon'),
            bottom: const TabBar(tabs: [Tab(text: 'Slovin'), Tab(text: 'Cochran')]),
          ),
          body: const TabBarView(children: [_SlovinTab(), _CochranTab()]),
        ),
      );
}

class _SlovinTab extends StatefulWidget {
  const _SlovinTab();

  @override
  State<_SlovinTab> createState() => _SlovinTabState();
}

class _SlovinTabState extends State<_SlovinTab> {
  final _population = TextEditingController();
  final _margin = TextEditingController(text: '5');
  SampleSizeResult? _result;
  String? _error;

  void _compute() {
    FocusScope.of(context).unfocus();
    setState(() {
      try {
        _result = SampleSize.slovin(
          population: SampleSize.parseInt(_population.text),
          marginOfError: SampleSize.parsePercent(_margin.text),
        );
        _error = null;
      } on SampleSizeInputError catch (e) {
        _result = null;
        _error = e.message;
      }
    });
  }

  @override
  void dispose() {
    _population.dispose();
    _margin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _FormulaCard(
            formula: 'n = N ÷ (1 + N × e²)',
            explanation: 'À utiliser quand tu connais la taille de la population (N). Formule simple, '
                'très utilisée dans les TFC et mémoires.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _population,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Taille de la population (N)', hintText: 'Ex. 1000'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _margin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Marge d\'erreur (e)', suffixText: '%'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _compute, child: const Text('Calculer')),
          _ResultView(result: _result, error: _error),
        ],
      );
}

class _CochranTab extends StatefulWidget {
  const _CochranTab();

  @override
  State<_CochranTab> createState() => _CochranTabState();
}

class _CochranTabState extends State<_CochranTab> {
  final _margin = TextEditingController(text: '5');
  final _proportion = TextEditingController(text: '50');
  final _population = TextEditingController();
  ConfidenceLevel _confidence = ConfidenceLevel.p95;
  SampleSizeResult? _result;
  String? _error;

  void _compute() {
    FocusScope.of(context).unfocus();
    setState(() {
      try {
        _result = SampleSize.cochran(
          confidence: _confidence,
          marginOfError: SampleSize.parsePercent(_margin.text),
          proportion: SampleSize.parsePercent(_proportion.text),
          population: _population.text.trim().isEmpty ? null : SampleSize.parseInt(_population.text),
        );
        _error = null;
      } on SampleSizeInputError catch (e) {
        _result = null;
        _error = e.message;
      }
    });
  }

  @override
  void dispose() {
    _margin.dispose();
    _proportion.dispose();
    _population.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _FormulaCard(
            formula: 'n₀ = Z² × p × (1 − p) ÷ e²',
            explanation: 'À utiliser pour une grande population ou une population inconnue. '
                'Si tu connais N, la correction pour population finie est appliquée.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ConfidenceLevel>(
            initialValue: _confidence,
            decoration: const InputDecoration(labelText: 'Niveau de confiance'),
            items: [
              for (final c in ConfidenceLevel.values)
                DropdownMenuItem(value: c, child: Text('${c.percent} % (Z = ${SampleSize.fmt(c.z)})')),
            ],
            onChanged: (v) => setState(() => _confidence = v ?? _confidence),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _margin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Marge d\'erreur (e)', suffixText: '%'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _proportion,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Proportion attendue (p)',
              suffixText: '%',
              helperText: 'Laisse 50 % si tu ne la connais pas.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _population,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Taille de la population (N), facultatif'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _compute, child: const Text('Calculer')),
          _ResultView(result: _result, error: _error),
        ],
      );
}

class _FormulaCard extends StatelessWidget {
  const _FormulaCard({required this.formula, required this.explanation});

  final String formula;
  final String explanation;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formula, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(explanation),
            ],
          ),
        ),
      );
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.error});

  final SampleSizeResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
      );
    }
    final r = result;
    if (r == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Taille de l\'échantillon', style: theme.textTheme.labelLarge),
          Text('${r.sampleSize} personnes', style: theme.textTheme.headlineMedium),
          if (r.warning != null) ...[
            const SizedBox(height: 8),
            Text(r.warning!, style: TextStyle(color: theme.colorScheme.tertiary)),
          ],
          const SizedBox(height: 16),
          Text('Le calcul, étape par étape', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final (i, step) in r.steps.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: theme.textTheme.labelSmall)),
              title: Text(step.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.formula, style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace')),
                  if (step.note != null) Text(step.note!),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Dans ton travail, cite la formule utilisée, justifie la marge d\'erreur choisie et reproduis ces étapes.',
          ),
        ],
      ),
    );
  }
}

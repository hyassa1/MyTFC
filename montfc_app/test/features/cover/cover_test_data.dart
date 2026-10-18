import 'dart:convert';
import 'dart:io';

import 'package:montfc/features/cover/domain/cover_layout.dart';

const unikinId = '00000000-0000-4000-8000-000000000301';
const genericId = '00000000-0000-4000-8000-000000000303';

/// Mises en page des modèles de démonstration (copiées de supabase/seed.sql).
Map<String, dynamic> layoutsJson() =>
    jsonDecode(File('test/fixtures/cover_layouts.json').readAsStringSync()) as Map<String, dynamic>;

CoverLayout layout(String id) => CoverLayout.fromJson(layoutsJson()[id] as Map<String, dynamic>);

/// Métadonnées publiques des modèles (contenu embarqué de l'application).
List<Map<String, dynamic>> coverTemplates() {
  final seed = jsonDecode(File('assets/seed/content.json').readAsStringSync()) as Map<String, dynamic>;
  return [for (final t in seed['cover_templates'] as List) Map<String, dynamic>.from(t as Map)];
}

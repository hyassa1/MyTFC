import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../domain/student_work.dart';
import 'works_repository.dart';

final worksRepositoryProvider = Provider<WorksRepository>((ref) => WorksRepository(ref.watch(localDatabaseProvider)));

/// Travail en cours (rechargé après chaque synchronisation).
final currentWorkProvider = FutureProvider<StudentWork?>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(worksRepositoryProvider).current();
});

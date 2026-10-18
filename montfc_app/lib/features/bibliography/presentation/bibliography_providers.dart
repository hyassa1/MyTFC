import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../data/bibliography_repository.dart';
import '../domain/apa.dart';
import '../domain/source.dart';

final bibliographyRepositoryProvider =
    Provider<BibliographyRepository>((ref) => BibliographyRepository(ref.watch(localDatabaseProvider)));

/// Sources de l'étudiant (rechargées après chaque modification et synchro).
final sourcesProvider = FutureProvider<List<Source>>((ref) {
  ref.watch(contentRevisionProvider);
  return ref.watch(bibliographyRepositoryProvider).all();
});

final bibliographyOrderProvider =
    NotifierProvider<BibliographyOrderController, BibliographyOrder>(BibliographyOrderController.new);

class BibliographyOrderController extends Notifier<BibliographyOrder> {
  @override
  BibliographyOrder build() => BibliographyOrder.alphabetical;

  void set(BibliographyOrder order) => state = order;
}

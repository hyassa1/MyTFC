import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/phone_number.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/bibliography/presentation/bibliography_screen.dart';
import '../../features/bibliography/presentation/source_form_screen.dart';
import '../../features/checklist/presentation/checklist_screen.dart';
import '../../features/cover/presentation/cover_screens.dart';
import '../../features/export/presentation/export_screen.dart';
import '../../features/guide/presentation/guide_screens.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/payment/presentation/purchase_screen.dart';
import '../../features/profile/presentation/profile_form_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/questionnaires/presentation/questionnaire_screens.dart';
import '../../features/sample_size/presentation/sample_size_screen.dart';
import '../../features/store/domain/offer.dart';
import '../../features/store/presentation/store_screen.dart';
import '../../features/templates/presentation/templates_screens.dart';
import 'auth_redirect.dart';
import 'routes.dart';

/// Routeur de l'application.
///
/// Les écrans des modules suivants remplaceront progressivement les écrans
/// « à venir ». La garde de connexion est dans auth_redirect.dart.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Réévalue les redirections à chaque changement d'état de connexion.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);


  String? from(GoRouterState state) => state.uri.queryParameters[Routes.fromParam];

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(ref.read(authControllerProvider), state.uri),
    routes: [
      GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen()),
      GoRoute(path: Routes.login, builder: (context, state) => LoginScreen(redirectTo: from(state))),
      GoRoute(
        path: Routes.otp,
        builder: (context, state) => switch (state.extra) {
          (phone: final PhoneNumber phone, redirectTo: final String? redirectTo) =>
            OtpScreen(phone: phone, redirectTo: redirectTo),
          // Ouverture directe sans numéro (lien, retour arrière) : étape 1.
          _ => LoginScreen(redirectTo: from(state)),
        },
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (context, state) => ProfileFormScreen(isSetup: true, redirectTo: from(state)),
      ),
      GoRoute(path: Routes.profile, builder: (context, state) => const ProfileScreen()),
      GoRoute(path: Routes.profileEdit, builder: (context, state) => const ProfileFormScreen()),
      GoRoute(
        path: Routes.guide,
        builder: (context, state) => const GuideScreen(),
        routes: [
          GoRoute(
            path: ':slug',
            builder: (context, state) => GuideChapterScreen(slug: state.pathParameters['slug']!),
          ),
        ],
      ),
      GoRoute(path: Routes.sampleSize, builder: (context, state) => const SampleSizeScreen()),
      GoRoute(path: Routes.checklist, builder: (context, state) => const ChecklistScreen()),
      GoRoute(
        path: Routes.cover,
        builder: (context, state) => const CoverTemplatesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => CoverEditorScreen(templateId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.bibliography,
        builder: (context, state) => const BibliographyScreen(),
        routes: [
          GoRoute(path: 'ajouter', builder: (context, state) => const SourceFormScreen()),
          GoRoute(
            path: 'source/:id',
            builder: (context, state) => SourceFormScreen(sourceId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: Routes.templates,
        builder: (context, state) => const TemplatesScreen(),
        routes: [
          GoRoute(path: ':id', builder: (context, state) => TemplateScreen(templateId: state.pathParameters['id']!)),
        ],
      ),
      GoRoute(
        path: Routes.questionnaires,
        builder: (context, state) => const QuestionnairesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => QuestionnaireScreen(templateId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(path: Routes.export, builder: (context, state) => const ExportScreen()),
      GoRoute(path: Routes.store, builder: (context, state) => const StoreScreen()),
      GoRoute(
        path: Routes.purchase,
        builder: (context, state) => switch (state.extra) {
          (offer: final Offer offer, resourceId: final String? resourceId) =>
            PurchaseScreen(offer: offer, resourceId: resourceId),
          // Ouverture directe sans offre : retour à la liste des offres.
          _ => const StoreScreen(),
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

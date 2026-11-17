import 'package:go_router/go_router.dart';

import '../features/browse/browse_screen.dart';

/// App routes. Onboarding, show detail, alerts and settings are added in
/// Phase 1/2 (see docs/SHOWWATCH_SPEC.md §11).
final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const BrowseScreen()),
  ],
);

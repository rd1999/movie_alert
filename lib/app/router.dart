import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/browse/browse_screen.dart';
import '../features/browse/movie_showtimes_screen.dart';
import '../features/onboarding/city_controller.dart';
import '../features/onboarding/city_picker_screen.dart';

/// Routes. Alerts and settings arrive in Phase 2 (spec §11).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    redirect: (context, state) {
      final hasCity = ref.read(selectedCityProvider) != null;
      if (!hasCity && state.matchedLocation != '/city') return '/city';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const BrowseScreen()),
      GoRoute(
        path: '/city',
        builder: (context, state) => const CityPickerScreen(),
      ),
      GoRoute(
        path: '/movie/:id',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return MovieShowtimesScreen(
            contentId: int.parse(state.pathParameters['id']!),
            movieSlug: q['slug'] ?? '',
            title: q['name'] ?? 'Showtimes',
          );
        },
      ),
    ],
  );
});

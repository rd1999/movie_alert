import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/alerts/alert_history_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/alerts/create_alert_screen.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/movie_showtimes_screen.dart';
import '../features/onboarding/city_controller.dart';
import '../features/onboarding/city_picker_screen.dart';
import '../features/onboarding/setup_screen.dart';

/// Two tabs (Browse, Alerts) plus full-screen routes on top.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    redirect: (context, state) {
      final hasCity = ref.read(selectedCityProvider) != null;
      if (!hasCity && state.matchedLocation != '/city') return '/city';
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _TabsScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const BrowseScreen(),
                routes: [
                  GoRoute(
                    path: 'movie/:id',
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
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/alerts',
                builder: (context, state) => const AlertsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => AlertHistoryScreen(
                      alertId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/city',
        builder: (context, state) => const CityPickerScreen(),
      ),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: '/new-alert',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return CreateAlertScreen(
            contentId: int.parse(q['id']!),
            movieSlug: q['slug']!,
            movieName: q['name'] ?? 'Movie',
            initialCinemaId: int.tryParse(q['cinema'] ?? ''),
          );
        },
      ),
    ],
  );
});

class _TabsScaffold extends StatelessWidget {
  const _TabsScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.local_movies_outlined),
          selectedIcon: Icon(Icons.local_movies),
          label: 'Browse',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          selectedIcon: Icon(Icons.notifications),
          label: 'Alerts',
        ),
      ],
    ),
  );
}

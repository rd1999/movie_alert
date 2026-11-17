import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../data/repo/showtime_repository.dart';

final moviesProvider =
    FutureProvider.family<Cached<List<MovieSummary>>, String>(
      (ref, cityKey) => ref.watch(showtimeRepositoryProvider).movies(cityKey),
    );

final showtimesProvider =
    FutureProvider.family<Cached<ShowtimesPage>, ShowtimesQuery>(
      (ref, q) => ref.watch(showtimeRepositoryProvider).showtimes(q),
    );

/// Every cinema in the city, including ones not showing a movie yet.
final cinemasProvider = FutureProvider.family<Cached<List<Cinema>>, String>(
  (ref, cityKey) => ref.watch(showtimeRepositoryProvider).cinemas(cityKey),
);

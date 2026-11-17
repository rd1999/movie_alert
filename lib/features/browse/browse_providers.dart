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

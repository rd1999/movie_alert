import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../sources/showtime_source.dart';

/// A value plus when it was fetched, for "last updated" (FR-9).
class Cached<T> {
  const Cached(this.value, this.fetchedAt);

  final T value;
  final DateTime fetchedAt;
}

typedef ShowtimesQuery = ({
  String cityKey,
  String movieSlug,
  int contentId,
  String? fmtGrpId,
  String? date,
});

/// In-memory TTL cache in front of a [ShowtimeSource]. Identical concurrent
/// requests share one fetch. Errors are never cached.
class ShowtimeRepository {
  ShowtimeRepository(this.source, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final ShowtimeSource source;
  final DateTime Function() _now;
  final _cache = <String, Cached<Object?>>{};
  final _inFlight = <String, Future<Object?>>{};

  static const citiesTtl = Duration(days: 7);
  static const moviesTtl = Duration(minutes: 30);
  static const cinemasTtl = Duration(days: 1);
  static const showtimesTtl = Duration(minutes: 2);

  Future<Cached<List<City>>> cities({bool refresh = false}) =>
      _get('cities', citiesTtl, refresh, source.cities);

  Future<Cached<List<MovieSummary>>> movies(
    String cityKey, {
    bool refresh = false,
  }) =>
      _get('movies:$cityKey', moviesTtl, refresh, () => source.movies(cityKey));

  Future<Cached<List<Cinema>>> cinemas(
    String cityKey, {
    bool refresh = false,
  }) => _get(
    'cinemas:$cityKey',
    cinemasTtl,
    refresh,
    () => source.cinemas(cityKey),
  );

  Future<Cached<ShowtimesPage>> showtimes(
    ShowtimesQuery q, {
    bool refresh = false,
  }) => _get(
    'showtimes:${q.cityKey}:${q.contentId}:${q.fmtGrpId}:${q.date}',
    showtimesTtl,
    refresh,
    () => source.showtimes(
      cityKey: q.cityKey,
      movieSlug: q.movieSlug,
      contentId: q.contentId,
      fmtGrpId: q.fmtGrpId,
      date: q.date,
    ),
  );

  Future<Cached<T>> _get<T>(
    String key,
    Duration ttl,
    bool refresh,
    Future<T> Function() load,
  ) async {
    final hit = _cache[key];
    if (!refresh && hit != null && _now().difference(hit.fetchedAt) < ttl) {
      return Cached(hit.value as T, hit.fetchedAt);
    }
    // Block body on purpose: returning the removed future from whenComplete
    // would make this future wait on itself.
    final pending = _inFlight[key] ??= load().whenComplete(() {
      _inFlight.remove(key);
    });
    final value = await pending as T;
    final entry = Cached<Object?>(value, _now());
    _cache[key] = entry;
    return Cached(value, entry.fetchedAt);
  }
}

final showtimeRepositoryProvider = Provider<ShowtimeRepository>(
  (ref) => ShowtimeRepository(ref.watch(showtimeSourceProvider)),
);

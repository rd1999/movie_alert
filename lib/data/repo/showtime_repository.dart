import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';

import '../db/app_database.dart';
import '../sources/showtime_source.dart';

/// A value plus when it was fetched, for "last updated" (FR-9).
class Cached<T> {
  const Cached(this.value, this.fetchedAt, {this.offline = false});

  final T value;
  final DateTime fetchedAt;

  /// True when the network failed and this is the last saved copy.
  final bool offline;
}

typedef ShowtimesQuery = ({
  String cityKey,
  String movieSlug,
  int contentId,
  String? fmtGrpId,
  String? date,
});

/// Failures where showing the last saved copy is honest: we couldn't reach
/// the site. A changed page format is *not* one of them (NFR-4).
bool isNetworkFailure(Object e) => switch (e) {
  SocketException() || HttpException() || TlsException() => true,
  TimeoutException() => true,
  HttpStatusException(:final statusCode) =>
    statusCode == 429 || statusCode >= 500,
  _ => false,
};

class _Codec<T> {
  const _Codec(this.encode, this.decode);

  final Object? Function(T) encode;
  final T Function(Object?) decode;
}

/// TTL cache in front of a [ShowtimeSource]: memory first, then the network,
/// then (on network failure only) the last copy saved on disk. Identical
/// concurrent requests share one fetch. Errors are never cached.
class ShowtimeRepository {
  ShowtimeRepository(this.source, {this.disk, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final ShowtimeSource source;
  final PersistentCache? disk;
  final DateTime Function() _now;
  final _cache = <String, Cached<Object?>>{};
  final _inFlight = <String, Future<Object?>>{};

  static const citiesTtl = Duration(days: 7);
  static const moviesTtl = Duration(minutes: 30);
  static const cinemasTtl = Duration(days: 1);
  static const showtimesTtl = Duration(minutes: 2);

  static List<T> Function(Object?) _listOf<T>(T Function(Json) f) =>
      (o) => [for (final e in o as List) f((e as Map).cast<String, Object?>())];

  static final _cities = _Codec<List<City>>(
    (v) => [for (final c in v) ModelJson.city(c)],
    _listOf(ModelJson.cityFrom),
  );
  static final _movies = _Codec<List<MovieSummary>>(
    (v) => [for (final m in v) ModelJson.movieSummary(m)],
    _listOf(ModelJson.movieSummaryFrom),
  );
  static final _cinemas = _Codec<List<Cinema>>(
    (v) => [for (final c in v) ModelJson.cinema(c)],
    _listOf(ModelJson.cinemaFrom),
  );
  static final _page = _Codec<ShowtimesPage>(
    ModelJson.showtimesPage,
    (o) => ModelJson.showtimesPageFrom((o as Map).cast<String, Object?>()),
  );

  Future<Cached<List<City>>> cities({bool refresh = false}) =>
      _get('cities', citiesTtl, refresh, source.cities, _cities);

  Future<Cached<List<MovieSummary>>> movies(
    String cityKey, {
    bool refresh = false,
  }) => _get(
    'movies:$cityKey',
    moviesTtl,
    refresh,
    () => source.movies(cityKey),
    _movies,
  );

  Future<Cached<List<Cinema>>> cinemas(
    String cityKey, {
    bool refresh = false,
  }) => _get(
    'cinemas:$cityKey',
    cinemasTtl,
    refresh,
    () => source.cinemas(cityKey),
    _cinemas,
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
    _page,
  );

  Future<Cached<T>> _get<T>(
    String key,
    Duration ttl,
    bool refresh,
    Future<T> Function() load,
    _Codec<T> codec,
  ) async {
    final hit = _cache[key];
    if (!refresh &&
        hit != null &&
        !hit.offline &&
        _now().difference(hit.fetchedAt) < ttl) {
      return Cached(hit.value as T, hit.fetchedAt);
    }
    // Block body on purpose: returning the removed future from whenComplete
    // would make this future wait on itself.
    final pending = _inFlight[key] ??= load().whenComplete(() {
      _inFlight.remove(key);
    });
    final T value;
    try {
      value = await pending as T;
    } catch (e) {
      if (isNetworkFailure(e)) {
        final saved = await _readDisk(key, codec);
        if (saved != null) {
          _cache[key] = Cached(saved.value, saved.fetchedAt, offline: true);
          return saved;
        }
      }
      rethrow;
    }
    final at = _now();
    _cache[key] = Cached<Object?>(value, at);
    unawaited(_writeDisk(key, value, at, codec));
    return Cached(value, at);
  }

  Future<Cached<T>?> _readDisk<T>(String key, _Codec<T> codec) async {
    try {
      final row = await disk?.read('${source.id}:$key');
      if (row == null) return null;
      return Cached(codec.decode(jsonDecode(row.$1)), row.$2, offline: true);
    } catch (_) {
      return null; // A corrupt or outdated cache entry is just a miss.
    }
  }

  Future<void> _writeDisk<T>(
    String key,
    T value,
    DateTime at,
    _Codec<T> codec,
  ) async {
    try {
      await disk?.write(
        '${source.id}:$key',
        jsonEncode(codec.encode(value)),
        at,
      );
    } catch (_) {
      // The offline copy is best-effort.
    }
  }
}

/// Overridden in `main()` with the SQLite store; null disables the
/// offline copy (tests).
final pageCacheProvider = Provider<PersistentCache?>((ref) => null);

final showtimeRepositoryProvider = Provider<ShowtimeRepository>(
  (ref) => ShowtimeRepository(
    ref.watch(showtimeSourceProvider),
    disk: ref.watch(pageCacheProvider),
  ),
);

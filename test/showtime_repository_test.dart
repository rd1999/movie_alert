import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/data/db/app_database.dart';
import 'package:movie_alert/data/repo/showtime_repository.dart';
import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/fake_source.dart';

class MemoryCache implements PersistentCache {
  final rows = <String, (String, DateTime)>{};

  @override
  Future<(String, DateTime)?> read(String key) async => rows[key];

  @override
  Future<void> write(String key, String json, DateTime at) async =>
      rows[key] = (json, at);
}

void main() {
  late FakeSource source;
  late DateTime now;
  late ShowtimeRepository repo;

  setUp(() {
    source = FakeSource();
    now = DateTime(2026, 11, 17, 10);
    repo = ShowtimeRepository(source, clock: () => now);
  });

  test('serves from cache within the TTL, refetches after', () async {
    final a = await repo.movies('kolkata');
    final b = await repo.movies('kolkata');
    expect(source.calls, ['movies:kolkata']);
    expect(b.fetchedAt, a.fetchedAt);

    now = now.add(ShowtimeRepository.moviesTtl);
    await repo.movies('kolkata');
    expect(source.calls, ['movies:kolkata', 'movies:kolkata']);
  });

  test('refresh bypasses the cache', () async {
    await repo.cities();
    await repo.cities(refresh: true);
    expect(source.calls, ['cities', 'cities']);
  });

  test('concurrent identical requests share one fetch', () async {
    await Future.wait([repo.cinemas('kolkata'), repo.cinemas('kolkata')]);
    expect(source.calls, ['cinemas:kolkata']);
  });

  test('keys include the query; errors are not cached', () async {
    final q = (
      cityKey: 'kolkata',
      movieSlug: 'm',
      contentId: 1,
      fmtGrpId: 'en',
      date: '2026-12-18',
    );
    await repo.showtimes(q);
    await repo.showtimes((
      cityKey: q.cityKey,
      movieSlug: q.movieSlug,
      contentId: q.contentId,
      fmtGrpId: q.fmtGrpId,
      date: '2026-12-19',
    ));
    expect(source.calls, hasLength(2));

    source.failWith = StateError('down');
    await expectLater(repo.movies('agra'), throwsStateError);
    source.failWith = null;
    await repo.movies('agra');
    expect(source.calls.where((c) => c == 'movies:agra'), hasLength(2));
  });

  group('offline copy (FR-9)', () {
    late MemoryCache disk;
    setUp(() {
      disk = MemoryCache();
      repo = ShowtimeRepository(source, disk: disk, clock: () => now);
    });

    final q = (
      cityKey: 'kolkata',
      movieSlug: 'test-doomsday',
      contentId: 176735,
      fmtGrpId: null,
      date: null,
    );

    test(
      'network failure serves the last saved copy, marked offline',
      () async {
        final online = await repo.showtimes(q);
        await pumpEventQueue();
        expect(disk.rows, hasLength(1));

        now = now.add(const Duration(hours: 3));
        source.failWith = const SocketException('no route');
        final offline = await repo.showtimes(q, refresh: true);
        expect(offline.offline, isTrue);
        expect(offline.fetchedAt, online.fetchedAt);
        expect(offline.value.cinemas.single.cinema.name, 'Test Mani Square');
        expect(offline.value.allShows.first.seatClasses.map((a) => a.label), [
          'EXECUTIVE',
          'RECLINER',
        ]);
      },
    );

    test('rate limiting and 5xx also fall back; 404 does not', () async {
      await repo.movies('kolkata');
      await pumpEventQueue();
      for (final code in [429, 503]) {
        source.failWith = HttpStatusException(code, Uri());
        expect((await repo.movies('kolkata', refresh: true)).offline, isTrue);
      }
      source.failWith = HttpStatusException(404, Uri());
      await expectLater(
        repo.movies('kolkata', refresh: true),
        throwsA(isA<HttpStatusException>()),
      );
    });

    test('a changed page format is an error, never stale data', () async {
      await repo.cinemas('kolkata');
      await pumpEventQueue();
      source.failWith = SourceFormatChanged('rails missing');
      await expectLater(
        repo.cinemas('kolkata', refresh: true),
        throwsA(isA<SourceFormatChanged>()),
      );
    });

    test('no saved copy -> the network error surfaces', () async {
      source.failWith = const SocketException('no route');
      await expectLater(repo.cities(), throwsA(isA<SocketException>()));
    });

    test('back online: fresh data replaces the offline copy', () async {
      await repo.movies('kolkata');
      await pumpEventQueue();
      source.failWith = const SocketException('no route');
      expect((await repo.movies('kolkata', refresh: true)).offline, isTrue);
      source.failWith = null;
      // Offline entries never satisfy the memory TTL.
      final fresh = await repo.movies('kolkata');
      expect(fresh.offline, isFalse);
    });
  });
}

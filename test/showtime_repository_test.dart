import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/data/repo/showtime_repository.dart';

import 'support/fake_source.dart';

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
}

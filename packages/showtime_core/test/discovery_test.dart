import 'dart:io';

import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_discovery.dart';
import 'support/synthetic_page.dart';

const parser = DistrictParser();

void main() {
  group('city sitemap', () {
    test('parses, dedupes and sorts cities', () {
      final cities = parser.parseCitySitemap(syntheticSitemap);
      expect(cities.map((c) => c.key), ['agra', 'kolkata', 'navi-mumbai']);
      expect(cities.last.name, 'Navi Mumbai');
    });

    test('broken sitemap throws', () {
      expect(
        () => parser.parseCitySitemap('<html>blocked</html>'),
        throwsA(isA<SourceFormatChanged>()),
      );
      expect(
        () => parser.parseCitySitemap('<urlset></urlset>'),
        throwsA(isA<SourceFormatChanged>()),
      );
    });
  });

  group('movies page', () {
    test('reads movie cards and skips other items', () {
      final movies = parser.parseMoviesPage(
        syntheticEdsPage([
          [quickLink('movies_home_v2')],
          [
            movieItem(176735, 'Test Doomsday', 'test-doomsday'),
            movieItem(2, 'Other', 'other'),
            movieItem(176735, 'Test Doomsday', 'test-doomsday'), // dup rail
          ],
        ]),
      );
      expect(movies.map((m) => m.contentId), [176735, 2]);
      final m = movies.first;
      expect(m.slug, 'test-doomsday');
      expect(m.name, 'Test Doomsday');
      expect(m.censor, 'UA13+');
      expect(m.durationMinutes, 165);
      expect(m.genres, ['Action']);
      expect(m.languages, ['English', 'Hindi']);
      expect(m.formats, ['3D', 'IMAX 3D']);
      expect(m.releaseDate, DateTime.utc(2026, 12, 17));
    });

    test('a card without web_url is a format change, not a skipped movie', () {
      expect(
        () => parser.parseMoviesPage(
          syntheticEdsPage([
            [movieItem(1, 'X', 'x', webUrl: 'https://elsewhere/x')],
          ]),
        ),
        throwsA(isA<SourceFormatChanged>()),
      );
    });

    test('page without EDS rails throws', () {
      expect(
        () => parser.parseMoviesPage(syntheticMoviePage()),
        throwsA(isA<SourceFormatChanged>()),
      );
    });
  });

  group('cinemas page', () {
    test('reads cinemas across rails, deduped and sorted', () {
      final cinemas = parser.parseCinemasPage(
        syntheticEdsPage([
          [cinemaItem(148, 'B Cinema')],
          [
            cinemaItem(148, 'B Cinema'),
            cinemaItem(1020736, 'A Cinema', cancellable: true),
          ],
        ]),
      );
      expect(cinemas.map((c) => c.id), [1020736, 148]);
      expect(cinemas.first.isCancellable, isTrue);
      expect(cinemas.last.isCancellable, isNull);
      expect(cinemas.last.distanceKm, closeTo(2.42, 0.01));
      expect(cinemas.last.latitude, 22.5);
    });
  });

  group('DistrictSource', () {
    test('routes each call to the right URL and parser', () async {
      final asked = <Uri>[];
      final source = DistrictSource((url) async {
        asked.add(url);
        if (url.host == 'cdn.district.in') return syntheticSitemap;
        if (url.path.startsWith('/movies/cinemas-in-')) {
          return syntheticEdsPage([
            [cinemaItem(1, 'C')],
          ]);
        }
        if (url.path.endsWith('-movie-tickets')) {
          return syntheticEdsPage([
            [movieItem(1, 'M', 'm')],
          ]);
        }
        return syntheticMoviePage();
      });

      expect(source.id, 'district');
      expect(await source.cities(), hasLength(3));
      expect((await source.movies('kolkata')).single.slug, 'm');
      expect((await source.cinemas('kolkata')).single.id, 1);
      final page = await source.showtimes(
        cityKey: 'kolkata',
        movieSlug: 'test-doomsday',
        contentId: 176735,
        fmtGrpId: 'Mm5dpqTqJz',
      );
      expect(page.cinemas, hasLength(2));
      expect(asked.map((u) => u.toString()), [
        'https://cdn.district.in/sitemap/sitemap-movies-city.xml',
        'https://www.district.in/movies/kolkata-movie-tickets',
        'https://www.district.in/movies/cinemas-in-kolkata',
        'https://www.district.in/movies/test-doomsday-movie-tickets-in-kolkata-MV176735?frmtid=mm5dpqtqjz',
      ]);
      expect(
        source
            .bookingUrl(
              cityKey: 'kolkata',
              movieSlug: 'test-doomsday',
              contentId: 176735,
              date: '2026-12-20',
            )
            .toString(),
        'https://www.district.in/movies/test-doomsday-movie-tickets-in-kolkata-MV176735?fromdate=2026-12-20',
      );
    });
  });

  // Local-only real pages saved 17 Nov 2026 (gitignored).
  final dir = 'test/fixtures/district';
  final sitemap = File('$dir/city_list.xml');
  final movies = File('$dir/movies_kolkata.html');
  final cinemas = File('$dir/cinemas_kolkata.html');
  group(
    'real discovery pages (17 Nov 2026)',
    () {
      test('783 cities incl. Kolkata', () {
        final cities = parser.parseCitySitemap(sitemap.readAsStringSync());
        expect(cities, hasLength(783));
        expect(cities.map((c) => c.key), contains('kolkata'));
      });

      test('Kolkata movies incl. Doomsday with its slug', () {
        final list = parser.parseMoviesPage(movies.readAsStringSync());
        expect(list, hasLength(14));
        final doomsday = list.singleWhere((m) => m.contentId == 176735);
        expect(doomsday.slug, 'avengers-doomsday');
        expect(doomsday.languages, ['English', 'Hindi']);
        expect(doomsday.releaseDate, DateTime.utc(2026, 12, 17));
      });

      test('Kolkata cinemas incl. PVR Mani Square', () {
        final list = parser.parseCinemasPage(cinemas.readAsStringSync());
        expect(list, hasLength(34));
        expect(list.map((c) => c.id), contains(1020736));
      });
    },
    skip: sitemap.existsSync() && movies.existsSync() && cinemas.existsSync()
        ? false
        : 'real fixtures not present (gitignored)',
  );
}

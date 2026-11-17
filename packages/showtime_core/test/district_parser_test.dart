import 'dart:io';

import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_page.dart';

const parser = DistrictParser();

void main() {
  group('synthetic default page (no query params)', () {
    late ShowtimesPage page;
    setUp(() => page = parser.parseShowtimesPage(syntheticMoviePage()));

    test('movie info', () {
      expect(page.movie.contentId, 176735);
      expect(page.movie.name, 'Test Movie: Doomsday');
      expect(page.movie.censor, 'TBA');
      expect(page.movie.durationMinutes, 165);
      expect(page.movie.isReleased, isTrue);
    });

    test('language/format groups keep raw id and expose lowercase key', () {
      expect(page.languageFormats.map((g) => g.language), ['English', 'Hindi']);
      expect(page.languageFormats.first.fmtGrpId, 'Mm5dpqTqJz');
      expect(page.languageFormats.first.key, 'mm5dpqtqjz');
      expect(page.languageFormats.first.sessionCount, 4);
    });

    test('picks key "fmt" and defaults listing date to first session date', () {
      expect(page.fmtGrpId, 'mm5dpqtqjz');
      expect(page.sessionDates, [
        '2026-12-17',
        '2026-12-18',
        '2026-12-19',
        '2026-12-20',
      ]);
      expect(page.listingDate, '2026-12-17');
    });

    test('cinemas', () {
      expect(page.cinemas.map((c) => c.cinema.id), [148, 2001]);
      final c = page.cinemas.first.cinema;
      expect(c.name, 'Test Cinema One, Kolkata');
      expect(c.chain, 'TestChain');
      expect(c.cityKey, 'kolkata');
      expect(c.isCancellable, isTrue);
      expect(c.distanceKm, 2.25);
      expect(c.latitude, 22.5);
      expect(c.path, '/test-cinema-c/148');
    });

    test('show fields', () {
      final s = page.cinemas.first.shows.first;
      expect(s.sessionId, '7868');
      expect(s.cinemaId, 148);
      expect(s.uniqueKey, '148:7868');
      expect(s.showTime, DateTime(2026, 12, 17, 10, 15));
      expect(s.rawShowTime, '2026-12-17T10:15');
      expect(s.audi, 'AUDI04');
      expect(s.screenFormat, 'MS INFINITY VISION 3D');
      expect(s.premiumLabel, 'DOLBY 7.1');
      expect(s.seatsAvailable, 242);
      expect(s.seatsTotal, 252);
      expect(s.availability, SeatAvailability.available);
      expect(s.statusLabel, 'Available');
      expect(s.maxTickets, 10);
      expect(s.tags, contains('ms_infinity_vision_3d'));
    });

    test('late-night show keeps its own date, blank label becomes null', () {
      final s = page.cinemas.first.shows[1];
      expect(s.showTime, DateTime(2026, 12, 18, 1));
      expect(s.premiumLabel, isNull);
      expect(s.availability, SeatAvailability.fillingFast);
    });

    test('status codes G/Y/R/D', () {
      expect(page.allShows.map((s) => s.availability), [
        SeatAvailability.available,
        SeatAvailability.fillingFast,
        SeatAvailability.almostFull,
        SeatAvailability.soldOut,
      ]);
    });

    test('seat classes', () {
      final classes = page.cinemas.first.shows.first.seatClasses;
      expect(classes, hasLength(2));
      expect(classes[0].label, 'PREMIUM');
      expect(classes[0].price, 540);
      expect(classes[0].available, 137);
      expect(classes[0].total, 143);
      expect(classes[1].price, 1100.5);
      expect(classes[1].availability, SeatAvailability.soldOut);
    });

    test('format matching looks at scrnFmt and premiumLabel', () {
      final pxl = page.cinemas[1].shows.first;
      expect(pxl.matchesFormat('pxl'), isTrue);
      expect(pxl.matchesFormat('ATMOS'), isTrue);
      expect(pxl.matchesFormat('imax'), isFalse);
    });
  });

  group('key selection', () {
    test('dated page uses key "fmt+date" and that listing date', () {
      final page = parser.parseShowtimesPage(
        syntheticMoviePage(
          dateQuery: '2026-12-20',
          extraSessionEntries: {'zdwddffdqq': <String, Object?>{}},
        ),
      );
      expect(page.listingDate, '2026-12-20');
      expect(page.cinemas, hasLength(2));
    });

    test('ambiguous entries throw instead of guessing', () {
      final html = syntheticMoviePage(
        mutate: (d) {
          final ss = _serverState(d);
          ss['queryState'] = {'frmtid': 'nope', 'fromdate': ''};
          (ss['movieSessions'] as Map)['other'] = <String, Object?>{};
          return d;
        },
      );
      expect(
        () => parser.parseShowtimesPage(html),
        throwsA(isA<SourceFormatChanged>()),
      );
    });
  });

  group('no shows vs. broken page (NFR-4)', () {
    test('empty arrangedSessions is a real empty result', () {
      final page = parser.parseShowtimesPage(
        syntheticMoviePage(arranged: [], sessionDates: []),
      );
      expect(page.cinemas, isEmpty);
      expect(page.listingDate, isNull);
    });

    test('no __NEXT_DATA__ throws', () {
      expect(
        () => parser.parseShowtimesPage(
          '<html><body>Access denied</body></html>',
        ),
        throwsA(isA<SourceFormatChanged>()),
      );
    });

    test('invalid JSON throws', () {
      expect(
        () => parser.parseShowtimesPage(
          '<script id="__NEXT_DATA__" type="application/json">{oops</script>',
        ),
        throwsA(isA<SourceFormatChanged>()),
      );
    });

    test('missing serverState throws with the path', () {
      final html = syntheticMoviePage(
        mutate: (d) {
          ((d['props'] as Map)['pageProps'] as Map)['data'] =
              <String, Object?>{};
          return d;
        },
      );
      expect(
        () => parser.parseShowtimesPage(html),
        throwsA(
          isA<SourceFormatChanged>().having(
            (e) => e.path,
            'path',
            r'$.props.pageProps.data.serverState',
          ),
        ),
      );
    });

    test('missing arrangedSessions throws', () {
      final html = syntheticMoviePage(
        mutate: (d) {
          final entry =
              (_serverState(d)['movieSessions'] as Map)['mm5dpqtqjz'] as Map;
          entry.remove('arrangedSessions');
          return d;
        },
      );
      expect(
        () => parser.parseShowtimesPage(html),
        throwsA(isA<SourceFormatChanged>()),
      );
    });

    test('session without seat counts throws', () {
      final s = session(sid: '1', cid: 1, showTime: '2026-12-17T10:00')
        ..remove('avail');
      final html = syntheticMoviePage(
        arranged: [
          cinema(1, 'X', [s]),
        ],
      );
      expect(
        () => parser.parseShowtimesPage(html),
        throwsA(
          isA<SourceFormatChanged>().having(
            (e) => e.path,
            'path',
            endsWith('.avail'),
          ),
        ),
      );
    });

    test('bad showTime throws', () {
      final s = session(sid: '1', cid: 1, showTime: 'tomorrow');
      expect(
        () => parser.parseShowtimesPage(
          syntheticMoviePage(
            arranged: [
              cinema(1, 'X', [s]),
            ],
          ),
        ),
        throwsA(isA<SourceFormatChanged>()),
      );
    });
  });

  // Local-only: real page saved from district.in on 17 Nov 2026 (gitignored).
  final real = File('test/fixtures/district/doomsday_kolkata_default.html');
  group(
    'real page: Doomsday, Kolkata, default (17 Nov 2026)',
    () {
      late ShowtimesPage page;
      setUpAll(() => page = parser.parseShowtimesPage(real.readAsStringSync()));

      test('matches what the site showed', () {
        expect(page.movie.contentId, 176735);
        expect(page.movie.name, 'Avengers: Doomsday');
        expect(page.fmtGrpId, 'mm5dpqtqjz');
        expect(page.languageFormats.map((g) => g.language), [
          'English',
          'Hindi',
        ]);
        expect(page.sessionDates, [
          '2026-12-17',
          '2026-12-18',
          '2026-12-19',
          '2026-12-20',
        ]);
        expect(page.listingDate, '2026-12-17');
        expect(page.cinemas, hasLength(8));
        expect(page.allShows, hasLength(60));
      });

      test(
        'PVR Mani Square (1020736) not listed yet — the origin-story case',
        () {
          expect(
            page.cinemas.map((c) => c.cinema.id),
            isNot(contains(1020736)),
          );
        },
      );

      test('every status code is known', () {
        final all = [
          ...page.allShows.map((s) => s.availability),
          ...page.allShows
              .expand((s) => s.seatClasses)
              .map((a) => a.availability),
        ];
        expect(all, isNot(contains(SeatAvailability.unknown)));
      });

      test('first show', () {
        final s = page.cinemas.first.shows.first;
        expect(page.cinemas.first.cinema.id, 148);
        expect(s.sessionId, '7868');
        expect(s.rawShowTime, '2026-12-17T02:15');
        expect(s.screenFormat, 'MS INFINITY VISION 3D');
        expect(s.premiumLabel, 'DOLBY 7.1');
        expect(s.seatsTotal, 252);
        expect(s.seatClasses.map((a) => a.label), [
          'NORMAL',
          'EXECUTIVE',
          'PREMIUM',
        ]);
      });
    },
    skip: real.existsSync() ? false : 'real fixture not present (gitignored)',
  );
}

Map<String, Object?> _serverState(Map<String, Object?> d) =>
    (((d['props'] as Map)['pageProps'] as Map)['data'] as Map)['serverState']
        as Map<String, Object?>;

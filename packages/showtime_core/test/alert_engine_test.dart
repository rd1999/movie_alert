import 'dart:convert';

import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

const maniSquare = 1020736;
const acropolis = 148;
const en = 'mm5dpqtqjz';
const hi = 'zdwddffdqq';

final t0 = DateTime.utc(2026, 11, 17, 10);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

ObservedShow show(
  int cinemaId,
  String sid, {
  String date = '2026-12-18',
  String time = '10:15',
  String fmt = en,
  String? screen = 'MS INFINITY VISION 3D',
  String? premium = 'DOLBY 7.1',
  int avail = 100,
}) => ObservedShow(
  cinemaId: cinemaId,
  cinemaName: cinemaId == maniSquare ? 'PVR Mani Square' : 'Cinema $cinemaId',
  sessionId: sid,
  fmtGrpId: fmt,
  listingDate: date,
  rawShowTime: '${date}T$time',
  seatsAvailable: avail,
  seatsTotal: 200,
  screenFormat: screen,
  premiumLabel: premium,
);

Snapshot snap(
  List<ObservedShow> shows, {
  Map<String, List<String>>? dates,
  DateTime? at,
}) => Snapshot(
  takenAt: at ?? t0,
  sessionDatesByGroup:
      dates ??
      {
        en: {for (final s in shows) s.listingDate}.toList()..sort(),
      },
  shows: shows,
);

Alert alert(
  AlertCondition condition, {
  Set<String> dates = const {},
  Set<String> groups = const {},
  AlertMode mode = AlertMode.once,
  DateTime? until,
}) => Alert(
  id: 'a1',
  cityKey: 'kolkata',
  movieContentId: 176735,
  movieSlug: 'avengers-doomsday',
  movieName: 'Avengers: Doomsday',
  condition: condition,
  createdAt: t0,
  dates: dates,
  fmtGrpIds: groups,
  mode: mode,
  activeUntil: until,
);

void main() {
  group('cinema opens — the origin story', () {
    final a = alert(
      const CinemaOpens({maniSquare}),
      dates: {'2026-12-18', '2026-12-19', '2026-12-20', '2026-12-21'},
    );

    test('quiet while the cinema is missing, fires when it appears', () {
      var r = AlertEngine.evaluate(a, snap([show(acropolis, '1')]), now: at(0));
      expect(r.event, isNull);
      expect(r.alert.status, AlertStatus.active);
      expect(r.alert.checkCount, 1);

      r = AlertEngine.evaluate(
        r.alert,
        snap([
          show(acropolis, '1'),
          show(maniSquare, '9', time: '13:40', screen: 'PXL 3D'),
          show(maniSquare, '8', time: '10:00', screen: 'PXL 3D'),
        ]),
        now: at(15),
      );
      final e = r.event!;
      expect(e.kind, AlertEventKind.opened);
      expect(e.title, 'Avengers: Doomsday: bookings open');
      expect(e.shows.map((s) => s.sessionId), ['8', '9']); // sorted by time
      expect(e.dates, ['2026-12-18']);
      expect(
        e.body(),
        'PVR Mani Square · 2026-12-18: '
        '10:00 PXL 3D DOLBY 7.1 (100 left), 13:40 PXL 3D DOLBY 7.1 (100 left)',
      );
      expect(r.alert.status, AlertStatus.fired);
    });

    test('ignores the cinema on dates outside the filter', () {
      final r = AlertEngine.evaluate(
        a.copyWith(lastCheckedAt: t0),
        snap([show(maniSquare, '9', date: '2026-12-25')]),
        now: at(15),
      );
      expect(r.event, isNull);
    });

    test('language filter', () {
      final hindiOnly = alert(const CinemaOpens({maniSquare}), groups: {hi});
      final r = AlertEngine.evaluate(
        hindiOnly,
        snap([show(maniSquare, '9', fmt: en)]),
        now: at(0),
      );
      expect(r.event, isNull);
    });

    test('already true on the first check -> "Already available"', () {
      final r = AlertEngine.evaluate(
        a,
        snap([show(maniSquare, '9')]),
        now: at(0),
      );
      expect(r.event!.kind, AlertEventKind.alreadyAvailable);
      expect(r.event!.title, 'Already available: Avengers: Doomsday');
    });
  });

  group('modes and de-duplication (FR-13, FR-17)', () {
    test('everyNewMatch notifies each new show exactly once', () {
      var a = alert(
        const CinemaOpens({maniSquare}),
        mode: AlertMode.everyNewMatch,
      ).copyWith(lastCheckedAt: t0);
      var r = AlertEngine.evaluate(
        a,
        snap([show(maniSquare, '1')]),
        now: at(15),
      );
      expect(r.event!.matchKeys, {'show:$maniSquare:1'});
      expect(r.alert.status, AlertStatus.active);

      r = AlertEngine.evaluate(
        r.alert,
        snap([show(maniSquare, '1')]),
        now: at(30),
      );
      expect(r.event, isNull, reason: 'same show must not notify twice');

      r = AlertEngine.evaluate(
        r.alert,
        snap([show(maniSquare, '1'), show(maniSquare, '2')]),
        now: at(45),
      );
      expect(r.event!.matchKeys, {'show:$maniSquare:2'});
      expect(r.event!.shows.single.sessionId, '2');
      a = r.alert;
      expect(a.notifiedKeys, {'show:$maniSquare:1', 'show:$maniSquare:2'});
    });

    test('fired / paused alerts are left alone', () {
      for (final status in [
        AlertStatus.fired,
        AlertStatus.paused,
        AlertStatus.error,
      ]) {
        final a = alert(
          const CinemaOpens({maniSquare}),
        ).copyWith(status: status);
        final r = AlertEngine.evaluate(
          a,
          snap([show(maniSquare, '1')]),
          now: at(0),
        );
        expect(r.event, isNull);
        expect(identical(r.alert, a), isTrue);
      }
    });
  });

  group('format opens', () {
    test('matches scrnFmt or premiumLabel, case-insensitive', () {
      final a = alert(const FormatOpens('pxl'));
      expect(
        AlertEngine.evaluate(
          a,
          snap([show(1, '1', screen: 'PXL 3D')]),
          now: at(0),
        ).event,
        isNotNull,
      );
      expect(
        AlertEngine.evaluate(
          a,
          snap([show(1, '1', premium: 'Pxl Laser')]),
          now: at(0),
        ).event,
        isNotNull,
      );
      expect(
        AlertEngine.evaluate(
          a,
          snap([show(1, '1', premium: null)]),
          now: at(0),
        ).event,
        isNull,
      );
    });

    test('restricted to cinemas', () {
      final a = alert(const FormatOpens('IMAX', cinemaIds: {maniSquare}));
      final r = AlertEngine.evaluate(
        a,
        snap([
          show(1, '1', screen: 'IMAX 3D'),
          show(maniSquare, '2', screen: '2D'),
        ]),
        now: at(0),
      );
      expect(r.event, isNull);
    });
  });

  group('date opens', () {
    final a = alert(
      const DateOpens(),
      dates: {'2026-12-21'},
    ).copyWith(lastCheckedAt: t0);

    test('fires when the date appears in sessionDates, even without pages', () {
      var r = AlertEngine.evaluate(
        a,
        snap(
          [],
          dates: {
            en: ['2026-12-18', '2026-12-19'],
          },
        ),
        now: at(15),
      );
      expect(r.event, isNull);
      r = AlertEngine.evaluate(
        r.alert,
        snap(
          [],
          dates: {
            en: ['2026-12-18', '2026-12-21'],
          },
        ),
        now: at(30),
      );
      expect(r.event!.matchKeys, {'date:2026-12-21'});
      expect(r.event!.shows, isEmpty);
      expect(r.event!.body(), 'Bookings open for 2026-12-21');
    });

    test('respects the language filter on sessionDates', () {
      final r = AlertEngine.evaluate(
        a.copyWith(fmtGrpIds: {hi}),
        snap(
          [],
          dates: {
            en: ['2026-12-21'],
            hi: ['2026-12-18'],
          },
        ),
        now: at(15),
      );
      expect(r.event, isNull);
    });

    test('with cinemas: needs a show at one of them on that date', () {
      final b = alert(
        const DateOpens(cinemaIds: {maniSquare}),
        dates: {'2026-12-21'},
      ).copyWith(lastCheckedAt: t0);
      expect(
        AlertEngine.evaluate(
          b,
          snap([show(1, '1', date: '2026-12-21')]),
          now: at(15),
        ).event,
        isNull,
      );
      final r = AlertEngine.evaluate(
        b,
        snap([show(maniSquare, '1', date: '2026-12-21')]),
        now: at(15),
      );
      expect(r.event!.matchKeys, {'date:2026-12-21'});
      expect(r.event!.shows, hasLength(1));
    });
  });

  group('new cinema anywhere', () {
    test('first check is a silent baseline, then new cinemas fire', () {
      final a = alert(const NewCinemaAnywhere(), mode: AlertMode.everyNewMatch);
      var r = AlertEngine.evaluate(
        a,
        snap([show(1, '1'), show(2, '2')]),
        now: at(0),
      );
      expect(r.event, isNull);
      expect(r.alert.notifiedKeys, {'cinema:1', 'cinema:2'});

      r = AlertEngine.evaluate(
        r.alert,
        snap([show(1, '1'), show(2, '3'), show(maniSquare, '4')]),
        now: at(15),
      );
      expect(r.event!.matchKeys, {'cinema:$maniSquare'});
      expect(r.event!.kind, AlertEventKind.opened);

      // A cinema that drops out and comes back is not "new".
      r = AlertEngine.evaluate(r.alert, snap([show(1, '1')]), now: at(30));
      r = AlertEngine.evaluate(
        r.alert,
        snap([show(1, '1'), show(2, '5')]),
        now: at(45),
      );
      expect(r.event, isNull);
    });
  });

  group('seats available', () {
    test('fires when seats free up and re-arms when they go again', () {
      final a = alert(
        const SeatsAvailable(2),
        mode: AlertMode.everyNewMatch,
      ).copyWith(lastCheckedAt: t0);
      var r = AlertEngine.evaluate(
        a,
        snap([show(1, '1', avail: 0)]),
        now: at(15),
      );
      expect(r.event, isNull);
      r = AlertEngine.evaluate(
        r.alert,
        snap([show(1, '1', avail: 3)]),
        now: at(30),
      );
      expect(r.event!.matchKeys, {'seats:1:1'});
      r = AlertEngine.evaluate(
        r.alert,
        snap([show(1, '1', avail: 4)]),
        now: at(45),
      );
      expect(r.event, isNull);
      r = AlertEngine.evaluate(
        r.alert,
        snap([show(1, '1', avail: 1)]),
        now: at(60),
      );
      expect(r.event, isNull);
      r = AlertEngine.evaluate(
        r.alert,
        snap([show(1, '1', avail: 2)]),
        now: at(75),
      );
      expect(r.event, isNotNull);
    });
  });

  group('expiry and failures', () {
    test('expires at activeUntil without notifying', () {
      final a = alert(const CinemaOpens({maniSquare}), until: at(60));
      final r = AlertEngine.evaluate(
        a,
        snap([show(maniSquare, '1')]),
        now: at(60),
      );
      expect(r.event, isNull);
      expect(r.alert.status, AlertStatus.expired);
      expect(AlertEngine.isExpired(a, at(59)), isFalse);
    });

    test('auto-pauses into error after 6 consecutive failures (FR-18)', () {
      var a = alert(const CinemaOpens({maniSquare}));
      for (var i = 0; i < 5; i++) {
        a = AlertEngine.recordFailure(a);
      }
      expect(a.status, AlertStatus.active);
      a = AlertEngine.recordFailure(a);
      expect(a.status, AlertStatus.error);
      expect(a.consecutiveFailures, 6);
    });

    test('a successful check resets the failure count', () {
      final a = AlertEngine.recordFailure(
        alert(const CinemaOpens({maniSquare})),
      );
      final r = AlertEngine.evaluate(a, snap([]), now: at(0));
      expect(r.alert.consecutiveFailures, 0);
    });
  });

  test('event body truncates long lists', () {
    final r = AlertEngine.evaluate(
      alert(const FormatOpens('3D')),
      snap([for (var c = 1; c <= 8; c++) show(c, '$c')]),
      now: at(0),
    );
    final lines = r.event!.body(maxLines: 3).split('\n');
    expect(lines, hasLength(4));
    expect(lines.last, '…and 5 more');
  });

  group('validation and JSON', () {
    test('validate()', () {
      expect(alert(const DateOpens()).validate(), isNotEmpty);
      expect(alert(const CinemaOpens({})).validate(), isNotEmpty);
      expect(alert(const FormatOpens(' ')).validate(), isNotEmpty);
      expect(alert(const SeatsAvailable(0)).validate(), isNotEmpty);
      expect(
        alert(const CinemaOpens({1}), dates: {'20-12-2026'}).validate(),
        isNotEmpty,
      );
      expect(
        alert(const CinemaOpens({1}), dates: {'2026-12-20'}).validate(),
        isEmpty,
      );
    });

    test('alerts round-trip through JSON', () {
      for (final c in <AlertCondition>[
        const CinemaOpens({maniSquare, 148}),
        const FormatOpens('PXL', cinemaIds: {maniSquare}),
        const DateOpens(cinemaIds: {1}),
        const NewCinemaAnywhere(),
        const SeatsAvailable(2, cinemaIds: {3}),
      ]) {
        final a = alert(
          c,
          dates: {'2026-12-20'},
          groups: {en},
          mode: AlertMode.everyNewMatch,
          until: at(600),
        ).copyWith(notifiedKeys: {'x'}, lastCheckedAt: at(5), checkCount: 3);
        final json = jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>;
        final back = Alert.fromJson(json);
        expect(back.toJson(), a.toJson());
        expect(back.condition.runtimeType, c.runtimeType);
      }
    });

    test('snapshots round-trip through JSON', () {
      final s = snap([show(1, '1'), show(2, '2', premium: null)], at: at(5));
      final back = Snapshot.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
      );
      expect(back.toJson(), s.toJson());
    });
  });
}

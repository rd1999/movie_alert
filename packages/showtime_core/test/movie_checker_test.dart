import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_page.dart';

const parser = DistrictParser();
const en = 'mm5dpqtqjz';
const hi = 'zdwddffdqq';
final now = DateTime.utc(2026, 11, 17, 10);

Alert alert(
  AlertCondition c, {
  Set<String> dates = const {},
  Set<String> groups = const {},
  String id = 'a',
}) => Alert(
  id: id,
  cityKey: 'kolkata',
  movieContentId: 176735,
  movieSlug: 'avengers-doomsday',
  movieName: 'Test Movie',
  condition: c,
  createdAt: now,
  dates: dates,
  fmtGrpIds: groups,
);

/// Fake site: serves synthetic pages and records every request.
class FakeSite {
  final requests = <String>[];

  /// (group, date) -> cinemas listed there.
  final Map<String, List<Map<String, Object?>>> listings = {};

  Future<ShowtimesPage> fetch({String? fmtGrpId, String? date}) async {
    requests.add('${fmtGrpId ?? '-'}/${date ?? '-'}');
    final g = fmtGrpId ?? en;
    final d = date ?? '2026-12-17';
    return parser.parseShowtimesPage(
      syntheticMoviePage(
        fmtQuery: g,
        dateQuery: date ?? '',
        arranged: listings['$g/$d'] ?? const [],
      ),
    );
  }
}

void main() {
  test('planner: groups', () {
    final groups = [
      const LanguageFormatGroup(language: 'English', fmtGrpId: 'Mm5dpqTqJz'),
      const LanguageFormatGroup(language: 'Hindi', fmtGrpId: 'zdwDdFFDqQ'),
    ];
    expect(
      CheckPlanner.groupsFor([
        alert(const NewCinemaAnywhere(), groups: {hi}),
      ], groups),
      [hi],
    );
    expect(
      CheckPlanner.groupsFor([
        alert(const NewCinemaAnywhere(), groups: {hi}),
        alert(const NewCinemaAnywhere()),
      ], groups),
      [en, hi],
    );
  });

  test('planner: dates', () {
    const sessionDates = ['2026-12-17', '2026-12-18', '2026-12-19'];
    expect(
      CheckPlanner.datesFor(
        [
          alert(const CinemaOpens({1}), dates: {'2026-12-18', '2026-12-25'}),
        ],
        en,
        sessionDates,
      ),
      {'2026-12-18'},
    );
    expect(
      CheckPlanner.datesFor(
        [
          alert(const CinemaOpens({1})),
        ],
        en,
        sessionDates,
      ),
      sessionDates.toSet(),
    );
    expect(
      CheckPlanner.datesFor(
        [
          alert(const DateOpens(), dates: {'2026-12-18'}),
        ],
        en,
        sessionDates,
      ),
      isEmpty,
      reason: 'date list alone answers "date opens"',
    );
    expect(
      CheckPlanner.datesFor(
        [
          alert(const CinemaOpens({1}), groups: {hi}),
        ],
        en,
        sessionDates,
      ),
      isEmpty,
    );
  });

  test('batches pages across alerts and fetches each once (FR-19)', () async {
    final site = FakeSite();
    site.listings['$en/2026-12-18'] = [
      cinema(1020736, 'Mani', [
        session(
          sid: '9',
          cid: 1020736,
          showTime: '2026-12-18T13:40',
          scrnFmt: 'PXL 3D',
        ),
      ]),
    ];
    final alerts = [
      alert(
        const CinemaOpens({1020736}),
        dates: {'2026-12-18'},
        groups: {en},
        id: 'mani',
      ),
      alert(
        const FormatOpens('PXL'),
        dates: {'2026-12-18', '2026-12-19'},
        groups: {en},
        id: 'pxl',
      ),
      alert(const DateOpens(), dates: {'2026-12-20'}, groups: {en}, id: 'date'),
    ];
    final result = await MovieChecker(site.fetch).check(alerts, now: now);

    expect(site.requests, ['-/-', '$en/2026-12-18', '$en/2026-12-19']);
    expect(result.pagesFetched, 3);
    final events = {
      for (final e in result.evaluations)
        if (e.event != null) e.alert.id: e.event!,
    };
    expect(events.keys, {'mani', 'pxl', 'date'});
    expect(events['mani']!.kind, AlertEventKind.alreadyAvailable);
    expect(events['date']!.matchKeys, {'date:2026-12-20'});
  });

  test('fetches other language groups only when asked', () async {
    final site = FakeSite();
    await MovieChecker(site.fetch).check([
      alert(const DateOpens(), dates: {'2026-12-20'}),
    ], now: now);
    expect(site.requests, ['-/-', '$hi/-']);
  });

  test('no active alerts -> no requests', () async {
    final site = FakeSite();
    final r = await MovieChecker(site.fetch).check([
      alert(const NewCinemaAnywhere()).copyWith(status: AlertStatus.fired),
    ], now: now);
    expect(site.requests, isEmpty);
    expect(r.evaluations.single.event, isNull);
  });

  test('a failed page fails the whole check (no partial "no shows")', () async {
    var calls = 0;
    Future<ShowtimesPage> fetch({String? fmtGrpId, String? date}) async {
      if (++calls == 2) throw SourceFormatChanged('boom');
      return parser.parseShowtimesPage(syntheticMoviePage());
    }

    expect(
      MovieChecker(fetch).check([
        alert(const CinemaOpens({1}), groups: {en}),
      ], now: now),
      throwsA(isA<SourceFormatChanged>()),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/features/browse/show_filter.dart';
import 'package:showtime_core/showtime_core.dart';

Show show(
  String sid,
  String time, {
  String fmt = '2D',
  num price = 300,
  SeatAvailability a = SeatAvailability.available,
}) => Show(
  sessionId: sid,
  cinemaId: 1,
  showTime: DateTime.parse(time),
  rawShowTime: time,
  seatsAvailable: 10,
  seatsTotal: 100,
  availability: a,
  screenFormat: fmt,
  seatClasses: [
    SeatClass(
      label: 'A',
      price: price,
      available: 1,
      total: 1,
      availability: SeatAvailability.available,
    ),
    SeatClass(
      label: 'B',
      price: price + 200,
      available: 1,
      total: 1,
      availability: SeatAvailability.available,
    ),
  ],
);

void main() {
  const pvr = Cinema(id: 1, name: 'PVR Mani Square, Kolkata');
  const inox = Cinema(id: 2, name: 'INOX Quest', chain: 'INOX');
  final cinemas = [
    CinemaShows(
      cinema: pvr,
      shows: [
        show('1', '2026-12-18T09:00', fmt: 'PXL 3D', price: 500),
        show('2', '2026-12-18T19:30', fmt: '2D', price: 250),
        show(
          '3',
          '2026-12-19T01:00',
          fmt: 'PXL 3D',
          a: SeatAvailability.soldOut,
        ),
      ],
    ),
    CinemaShows(
      cinema: inox,
      shows: [show('4', '2026-12-18T14:00', fmt: 'IMAX 3D', price: 800)],
    ),
  ];
  List<String> ids(ShowFilter f) => [
    for (final c in f.apply(cinemas))
      for (final s in c.shows) s.sessionId,
  ];

  test('empty filter keeps everything', () {
    expect(ids(const ShowFilter()), ['1', '2', '3', '4']);
    expect(const ShowFilter().activeCount, 0);
  });

  test('day parts, with 01:00 counted as night', () {
    expect(DayPart.of(DateTime(2026, 12, 19, 1)), DayPart.night);
    expect(DayPart.of(DateTime(2026, 12, 18, 9)), DayPart.morning);
    expect(DayPart.of(DateTime(2026, 12, 18, 14)), DayPart.afternoon);
    expect(DayPart.of(DateTime(2026, 12, 18, 19, 30)), DayPart.evening);
    expect(ids(const ShowFilter(dayParts: {DayPart.night})), ['3']);
  });

  test('chain from source key or first word of the name', () {
    expect(ShowFilter.chainOf(pvr), 'PVR');
    expect(ShowFilter.chainOf(inox), 'INOX');
    expect(ids(const ShowFilter(chains: {'INOX'})), ['4']);
  });

  test('format, price (cheapest seat), sold out, combined', () {
    expect(ids(const ShowFilter(formats: {'PXL 3D'})), ['1', '3']);
    expect(ids(const ShowFilter(maxPrice: 300)), ['2', '3']);
    expect(ids(const ShowFilter(hideSoldOut: true)), ['1', '2', '4']);
    const combined = ShowFilter(
      formats: {'PXL 3D'},
      hideSoldOut: true,
      chains: {'PVR'},
    );
    expect(ids(combined), ['1']);
    expect(combined.activeCount, 3);
  });

  test('cinemas with no matching shows disappear', () {
    final out = const ShowFilter(formats: {'IMAX 3D'}).apply(cinemas);
    expect(out.single.cinema.id, 2);
  });

  group('hall features', () {
    Show hall(
      String sid,
      String fmt,
      String? premium, {
      List<String> tags = const [],
    }) => Show(
      sessionId: sid,
      cinemaId: 1,
      showTime: DateTime(2026, 12, 18, 10),
      rawShowTime: '2026-12-18T10:00',
      seatsAvailable: 5,
      seatsTotal: 10,
      availability: SeatAvailability.available,
      screenFormat: fmt,
      premiumLabel: premium,
      tags: tags,
    );
    final shows = [
      CinemaShows(
        cinema: pvr,
        shows: [
          hall('a', 'MS INFINITY VISION 3D', 'DOLBY 7.1'),
          hall('b', 'MS INFINITY VISION 3D', 'RECLINERS', tags: ['recliner']),
          hall('c', '2D', 'DOLBY ATMOS', tags: ['recliner']),
          hall('d', 'IMAX 3D', '2K LASER DOLBY 7.1'),
        ],
      ),
    ];
    HallFeature f(String id) =>
        HallFeatures.known.firstWhere((x) => x.id == id);
    List<String> pick(Set<HallFeature> features) => [
      for (final c in ShowFilter(features: features).apply(shows))
        for (final s in c.shows) s.sessionId,
    ];

    test('OR within a group', () {
      expect(pick({f('atmos'), f('dolby-7-1')}), ['a', 'c', 'd']);
    });

    test('AND across groups', () {
      expect(pick({f('3d'), f('recliner')}), ['b']);
      expect(pick({f('atmos'), f('recliner')}), ['c']);
      expect(pick({f('2d'), f('dolby-7-1')}), isEmpty);
    });

    test('active count counts groups', () {
      expect(
        ShowFilter(
          features: {f('atmos'), f('dolby-7-1'), f('recliner')},
        ).activeCount,
        2,
      );
    });
  });
}

import 'dart:io';

import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

Show show({
  String? fmt,
  String? premium,
  List<String> tags = const [],
  List<String> areas = const [],
}) => Show(
  sessionId: '1',
  cinemaId: 1,
  showTime: DateTime(2026, 12, 18, 10),
  rawShowTime: '2026-12-18T10:00',
  seatsAvailable: 1,
  seatsTotal: 1,
  availability: SeatAvailability.available,
  screenFormat: fmt,
  premiumLabel: premium,
  tags: tags,
  seatClasses: [
    for (final a in areas)
      SeatClass(
        label: a,
        price: 1,
        available: 1,
        total: 1,
        availability: SeatAvailability.available,
      ),
  ],
);

Set<String> ids(Show s) => {for (final f in HallFeatures.of(s)) f.id};

void main() {
  test('real labels seen on 17 Nov 2026', () {
    expect(
      ids(show(fmt: 'MS INFINITY VISION 3D', premium: '2K LASER DOLBY 7.1')),
      {'3d', 'infinity', 'laser', 'dolby-7-1'},
    );
    expect(
      ids(show(fmt: 'MS INFINITY VISION 3D SCREEN X', premium: 'RECLINERS')),
      {'3d', 'infinity', 'screenx', 'recliner'},
    );
    expect(ids(show(fmt: 'MS INFINITY VISION 3D', premium: 'INSIGNIA')), {
      '3d',
      'infinity',
      'insignia',
    });
  });

  test('2D unless 3D or 4D, and common formats', () {
    expect(ids(show(fmt: '2D')), {'2d'});
    expect(ids(show(fmt: 'IMAX 3D')), {'imax', '3d'});
    expect(ids(show(fmt: '4DX')), {'4dx'});
    expect(ids(show(fmt: 'P[XL] 2D', premium: 'DOLBY ATMOS')), {
      'pxl',
      '2d',
      'atmos',
    });
  });

  test('seating from tags and seat-class names; no false positives', () {
    expect(ids(show(fmt: '2D', tags: ['recliner', 'wheelchair_friendly'])), {
      '2d',
      'recliner',
      'wheelchair',
    });
    expect(ids(show(fmt: '2D', areas: ['ROYAL RECLINER', 'COUPLE SEATS'])), {
      '2d',
      'recliner',
      'couple',
    });
    // "price_..." must not look like ICE; "premium" tag isn't a feature.
    expect(ids(show(fmt: '2D', tags: ['price_500_600', 'premium'])), {'2d'});
  });

  test('unknown premium labels are kept as raw "other" features', () {
    final f = HallFeatures.of(show(fmt: '2D', premium: 'STARLIGHT DECK'));
    final other = f.singleWhere((x) => x.group == HallFeatureGroup.other);
    expect(other.label, 'STARLIGHT DECK');
    expect(other.id, 'label:STARLIGHT DECK');
  });

  final real = File('test/fixtures/district/doomsday_kolkata_default.html');
  test(
    'every show on the real page gets a dimension; nothing falls to "other"',
    () {
      final page = const DistrictParser().parseShowtimesPage(
        real.readAsStringSync(),
      );
      for (final s in page.allShows) {
        final f = HallFeatures.of(s);
        expect(f.any((x) => x.group == HallFeatureGroup.dimension), isTrue);
        expect(f.where((x) => x.group == HallFeatureGroup.other), isEmpty);
      }
    },
    skip: real.existsSync() ? false : 'real fixture not present',
  );
}

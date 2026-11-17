import 'dart:convert';
import 'dart:io';

import 'package:showtime_core/showtime_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_discovery.dart';
import 'support/synthetic_page.dart';

const parser = DistrictParser();

/// Encode -> JSON text -> decode -> encode must be stable.
void roundTrip<T>(T value, Json Function(T) enc, T Function(Json) dec) {
  final first = enc(value);
  final back = dec(jsonDecode(jsonEncode(first)) as Json);
  expect(enc(back), first);
}

void main() {
  test('showtimes page round-trips (synthetic)', () {
    final page = parser.parseShowtimesPage(syntheticMoviePage());
    roundTrip(page, ModelJson.showtimesPage, ModelJson.showtimesPageFrom);
    final back = ModelJson.showtimesPageFrom(
      jsonDecode(jsonEncode(ModelJson.showtimesPage(page))) as Json,
    );
    expect(back.allShows.first.showTime, page.allShows.first.showTime);
    expect(back.allShows.last.availability, SeatAvailability.soldOut);
    expect(back.cinemas.first.shows.first.seatClasses.last.price, 1100.5);
  });

  test('movies, cinemas and cities round-trip', () {
    for (final m in parser.parseMoviesPage(
      syntheticEdsPage([
        [movieItem(1, 'M', 'm')],
      ]),
    )) {
      roundTrip(m, ModelJson.movieSummary, ModelJson.movieSummaryFrom);
    }
    for (final c in parser.parseCinemasPage(
      syntheticEdsPage([
        [cinemaItem(1, 'C', cancellable: true)],
      ]),
    )) {
      roundTrip(c, ModelJson.cinema, ModelJson.cinemaFrom);
    }
    roundTrip(
      const City(key: 'navi-mumbai', name: 'Navi Mumbai'),
      ModelJson.city,
      ModelJson.cityFrom,
    );
  });

  test('unknown availability names decode as unknown', () {
    final j = ModelJson.seatClass(
      const SeatClass(
        label: 'X',
        price: 1,
        available: 1,
        total: 1,
        availability: SeatAvailability.available,
      ),
    )..['status'] = 'brandNew';
    expect(ModelJson.seatClassFrom(j).availability, SeatAvailability.unknown);
  });

  final real = File('test/fixtures/district/doomsday_kolkata_default.html');
  test(
    'real page round-trips',
    () {
      final page = parser.parseShowtimesPage(real.readAsStringSync());
      roundTrip(page, ModelJson.showtimesPage, ModelJson.showtimesPageFrom);
    },
    skip: real.existsSync() ? false : 'real fixture not present (gitignored)',
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/features/onboarding/nearest_city.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/test_app.dart';

class FakeLocation implements LocationGateway {
  FakeLocation(this.result);

  final Object result; // List<String> or an exception to throw

  @override
  Future<List<String>> placeNames() async {
    if (result case final List<String> names) return names;
    throw result;
  }
}

void main() {
  const cities = [
    City(key: 'kolkata', name: 'Kolkata'),
    City(key: 'bengaluru', name: 'Bengaluru'),
    City(key: 'gurgaon', name: 'Gurgaon'),
    City(key: 'new-delhi', name: 'New Delhi'),
    City(key: 'navi-mumbai', name: 'Navi Mumbai'),
    City(key: 'howrah', name: 'Howrah'),
  ];

  group('CityMatcher', () {
    test('exact names, case and punctuation insensitive', () {
      expect(CityMatcher.match(cities, ['Kolkata'])?.key, 'kolkata');
      expect(CityMatcher.match(cities, ['Navi Mumbai'])?.key, 'navi-mumbai');
      expect(CityMatcher.match(cities, ['Kolkata District'])?.key, 'kolkata');
    });

    test('aliases for renamed cities', () {
      expect(CityMatcher.match(cities, ['Bangalore'])?.key, 'bengaluru');
      expect(CityMatcher.match(cities, ['Gurugram'])?.key, 'gurgaon');
      expect(CityMatcher.match(cities, ['Delhi'])?.key, 'new-delhi');
    });

    test('most specific name that matches wins', () {
      // A suburb not in the list, then its district, then the state.
      expect(
        CityMatcher.match(cities, [
          'Salt Lake City',
          'Howrah',
          'West Bengal',
        ])?.key,
        'howrah',
      );
      expect(CityMatcher.match(cities, ['Nowhere', 'Some State']), isNull);
    });

    final sitemap = File(
      'packages/showtime_core/test/fixtures/district/city_list.xml',
    );
    test(
      'every alias points at a real city key',
      () {
        final keys = {
          for (final c in const DistrictParser().parseCitySitemap(
            sitemap.readAsStringSync(),
          ))
            c.key,
        };
        for (final target in CityMatcher.aliases.values.toSet()) {
          expect(keys, contains(target));
        }
      },
      skip: sitemap.existsSync() ? false : 'real sitemap not present',
    );
  });

  group('Use my location', () {
    testWidgets('picks the matching city', (tester) async {
      final app = TestApp()
        ..location = FakeLocation(['Kolkata', 'West Bengal']);
      await app.pump(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(find.text('Test Doomsday'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('city.key'), 'kolkata');
    });

    testWidgets('explains when the location cannot be used', (tester) async {
      final app = TestApp()
        ..location = FakeLocation(
          const LocationUnavailable('Location permission was not given.'),
        );
      await app.pump(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(find.text('Location permission was not given.'), findsOneWidget);
      expect(find.text('Choose your city'), findsOneWidget);
    });

    testWidgets('no matching city asks the user to pick', (tester) async {
      final app = TestApp()..location = FakeLocation(['Atlantis']);
      await app.pump(tester);
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No listings city matches "Atlantis"'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}

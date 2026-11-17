import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../core/prefs/prefs.dart';
import '../../data/repo/showtime_repository.dart';

/// The user's city, persisted across launches (FR-1).
class SelectedCity extends Notifier<City?> {
  static const _key = 'city.key';

  @override
  City? build() {
    final key = ref.watch(sharedPrefsProvider).getString(_key);
    return key == null ? null : City(key: key, name: City.nameFromKey(key));
  }

  Future<void> select(City city) async {
    await ref.read(sharedPrefsProvider).setString(_key, city.key);
    state = city;
  }
}

final selectedCityProvider = NotifierProvider<SelectedCity, City?>(
  SelectedCity.new,
);

final citiesProvider = FutureProvider<List<City>>(
  (ref) async => (await ref.watch(showtimeRepositoryProvider).cities()).value,
);

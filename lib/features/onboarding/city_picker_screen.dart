import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/widgets/error_view.dart';
import 'city_controller.dart';
import 'nearest_city.dart';

/// Searchable list of ~783 cities (FR-1). GPS "nearest city" comes later.
class CityPickerScreen extends ConsumerStatefulWidget {
  const CityPickerScreen({super.key});

  @override
  ConsumerState<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends ConsumerState<CityPickerScreen> {
  String _query = '';
  bool _locating = false;

  Future<void> _useLocation(List<City> all) async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final names = await ref.read(locationGatewayProvider).placeNames();
      final city = CityMatcher.match(all, names);
      if (city == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              names.isEmpty
                  ? "Couldn't tell which city you're in. Please pick it."
                  : 'No listings city matches "${names.first}". '
                        'Please pick the nearest one.',
            ),
          ),
        );
        return;
      }
      await ref.read(selectedCityProvider.notifier).select(city);
      messenger.showSnackBar(
        SnackBar(content: Text('City set to ${city.name}')),
      );
      if (mounted) context.go('/');
    } on LocationUnavailable catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    final current = ref.watch(selectedCityProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your city'),
        automaticallyImplyLeading: current != null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              autofocus: current == null,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search cities',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: cities.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(citiesProvider),
              ),
              data: (all) {
                final list = _filter(all);
                final locate = ListTile(
                  leading: _locating
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  title: const Text('Use my location'),
                  subtitle: const Text(
                    'Only used to pick your city; never sent to the '
                    'listings site',
                  ),
                  onTap: _locating ? null : () => _useLocation(all),
                );
                if (list.isEmpty) {
                  return ListView(
                    children: [
                      locate,
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No city matches')),
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  itemCount: list.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) return locate;
                    final city = list[i - 1];
                    return ListTile(
                      title: Text(city.name),
                      trailing: city.key == current?.key
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () async {
                        await ref
                            .read(selectedCityProvider.notifier)
                            .select(city);
                        if (context.mounted) context.go('/');
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<City> _filter(List<City> all) {
    if (_query.isEmpty) return all;
    final starts = <City>[];
    final contains = <City>[];
    for (final c in all) {
      final n = c.name.toLowerCase();
      if (n.startsWith(_query)) {
        starts.add(c);
      } else if (n.contains(_query)) {
        contains.add(c);
      }
    }
    return [...starts, ...contains];
  }
}

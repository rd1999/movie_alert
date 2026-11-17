import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/widgets/error_view.dart';
import 'city_controller.dart';

/// Searchable list of ~783 cities (FR-1). GPS "nearest city" comes later.
class CityPickerScreen extends ConsumerStatefulWidget {
  const CityPickerScreen({super.key});

  @override
  ConsumerState<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends ConsumerState<CityPickerScreen> {
  String _query = '';

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
                if (list.isEmpty) {
                  return const Center(child: Text('No city matches'));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final city = list[i];
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

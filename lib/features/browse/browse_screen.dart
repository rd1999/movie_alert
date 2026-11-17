import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../app/widgets/error_view.dart';
import '../../data/repo/showtime_repository.dart';
import '../onboarding/city_controller.dart';
import 'browse_providers.dart';

/// Movies with bookings open in the selected city (FR-4, FR-9).
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(selectedCityProvider);
    if (city == null) return const SizedBox.shrink(); // router redirects
    final movies = ref.watch(moviesProvider(city.key));

    Future<void> refresh() async {
      await ref
          .read(showtimeRepositoryProvider)
          .movies(city.key, refresh: true);
      ref.invalidate(moviesProvider(city.key));
      await ref.read(moviesProvider(city.key).future);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ShowWatch'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/city'),
            icon: const Icon(Icons.place_outlined),
            label: Text(city.name),
          ),
        ],
      ),
      body: movies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(moviesProvider(city.key)),
        ),
        data: (cached) => RefreshIndicator(
          onRefresh: refresh,
          child: cached.value.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Text('No movies are bookable here right now.'),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: cached.value.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == cached.value.length) {
                      return _Footer(fetchedAt: cached.fetchedAt);
                    }
                    return _MovieTile(movie: cached.value[i]);
                  },
                ),
        ),
      ),
    );
  }
}

class _MovieTile extends StatelessWidget {
  const _MovieTile({required this.movie});

  final MovieSummary movie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = movie.releaseDate;
    final upcoming = release != null && release.isAfter(DateTime.now());
    final meta = [
      ?movie.censor,
      if (movie.durationMinutes case final d?) '${d ~/ 60}h ${d % 60}m',
      if (movie.genres.isNotEmpty) movie.genres.take(2).join(', '),
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 72,
          child: movie.posterUrl == null
              ? const ColoredBox(color: Colors.black12)
              : Image.network(
                  movie.posterUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Colors.black12),
                ),
        ),
      ),
      title: Text(movie.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty) Text(meta),
          Text(
            [
              movie.languages.join(', '),
              movie.formats.join(', '),
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (upcoming)
            Text(
              'Releases ${Fmt.day(release.toLocal())} · advance booking',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
        ],
      ),
      isThreeLine: true,
      onTap: () => context.push(
        Uri(
          path: '/movie/${movie.contentId}',
          queryParameters: {'slug': movie.slug, 'name': movie.name},
        ).toString(),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.fetchedAt});

  final DateTime fetchedAt;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      'Updated ${Fmt.ago(fetchedAt)} · Data from public cinema listings',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

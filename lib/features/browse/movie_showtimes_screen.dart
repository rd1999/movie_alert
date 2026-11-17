import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../app/widgets/availability.dart';
import '../../app/widgets/error_view.dart';
import '../../data/repo/showtime_repository.dart';
import '../../data/sources/showtime_source.dart';
import '../onboarding/city_controller.dart';
import '../show_detail/booking_launcher.dart';
import '../show_detail/show_detail_sheet.dart';
import 'browse_providers.dart';

/// Date chips, language selector, format filter, cinema list with show chips
/// (FR-5, FR-6, FR-8 partial, FR-9).
class MovieShowtimesScreen extends ConsumerStatefulWidget {
  const MovieShowtimesScreen({
    super.key,
    required this.contentId,
    required this.movieSlug,
    required this.title,
  });

  final int contentId;
  final String movieSlug;
  final String title;

  @override
  ConsumerState<MovieShowtimesScreen> createState() =>
      _MovieShowtimesScreenState();
}

class _MovieShowtimesScreenState extends ConsumerState<MovieShowtimesScreen> {
  String? _fmt;
  String? _date;
  String? _formatFilter;
  Cached<ShowtimesPage>? _last;

  ShowtimesQuery _query(String cityKey) => (
    cityKey: cityKey,
    movieSlug: widget.movieSlug,
    contentId: widget.contentId,
    fmtGrpId: _fmt,
    date: _date,
  );

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(selectedCityProvider);
    if (city == null) return const SizedBox.shrink();
    final q = _query(city.key);
    final async = ref.watch(showtimesProvider(q));
    if (async.value case final v?) _last = v;
    final cached = async.value ?? (async.isLoading ? _last : null);

    Future<void> refresh() async {
      await ref.read(showtimeRepositoryProvider).showtimes(q, refresh: true);
      ref.invalidate(showtimesProvider(q));
      await ref.read(showtimesProvider(q).future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cached?.value.movie.name ?? widget.title),
            if (cached != null)
              Text(
                '${city.name} · updated ${Fmt.ago(cached.fetchedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open booking',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openBooking(
              context,
              ref
                  .read(showtimeSourceProvider)
                  .bookingUrl(
                    cityKey: city.key,
                    movieSlug: widget.movieSlug,
                    contentId: widget.contentId,
                    fmtGrpId: cached?.value.fmtGrpId,
                    date: cached?.value.listingDate,
                  ),
            ),
          ),
        ],
        bottom: async.isLoading && cached != null
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: switch ((async, cached)) {
        (AsyncError(:final error), _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(showtimesProvider(q)),
        ),
        (_, null) => const Center(child: CircularProgressIndicator()),
        (_, final c?) => RefreshIndicator(
          onRefresh: refresh,
          child: _body(context, c.value),
        ),
      },
    );
  }

  Widget _body(BuildContext context, ShowtimesPage page) {
    final theme = Theme.of(context);
    final formats = <String>{
      for (final s in page.allShows) ?s.screenFormat,
    }.toList()..sort();
    final filtered = [
      for (final cs in page.cinemas)
        if (_filterShows(cs.shows) case final shows when shows.isNotEmpty)
          CinemaShows(cinema: cs.cinema, shows: shows),
    ];
    final showCount = filtered.fold<int>(0, (n, c) => n + c.shows.length);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (page.languageFormats.length > 1)
          _ChipRow(
            children: [
              for (final g in page.languageFormats)
                ChoiceChip(
                  label: Text(g.language),
                  selected: g.key == page.fmtGrpId,
                  onSelected: (_) => setState(() {
                    _fmt = g.key;
                    _date = null;
                    _formatFilter = null;
                  }),
                ),
            ],
          ),
        if (page.sessionDates.isNotEmpty)
          _ChipRow(
            children: [
              for (final d in page.sessionDates)
                ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Fmt.dateChip(d).$1),
                      Text(Fmt.dateChip(d).$2),
                    ],
                  ),
                  selected: d == page.listingDate,
                  onSelected: (_) => setState(() {
                    _fmt = page.fmtGrpId;
                    _date = d;
                  }),
                ),
            ],
          ),
        if (formats.length > 1)
          _ChipRow(
            children: [
              FilterChip(
                label: const Text('All formats'),
                selected: _formatFilter == null,
                onSelected: (_) => setState(() => _formatFilter = null),
              ),
              for (final f in formats)
                FilterChip(
                  label: Text(f),
                  selected: _formatFilter == f,
                  onSelected: (_) => setState(() => _formatFilter = f),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            page.listingDate == null
                ? 'No bookable dates yet'
                : '${Fmt.listingDate(page.listingDate!)} · '
                      '${filtered.length} cinemas · $showCount shows',
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No shows listed for this selection.')),
          ),
        for (final cs in filtered)
          _CinemaCard(
            cinemaShows: cs,
            listingDate: page.listingDate!,
            onShowTap: (show) => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => ShowDetailSheet(
                movieName: page.movie.name,
                cinema: cs.cinema,
                show: show,
                listingDate: page.listingDate!,
                bookingUrl: ref
                    .read(showtimeSourceProvider)
                    .bookingUrl(
                      cityKey: ref.read(selectedCityProvider)!.key,
                      movieSlug: widget.movieSlug,
                      contentId: widget.contentId,
                      fmtGrpId: page.fmtGrpId,
                      date: page.listingDate,
                    ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Data from public cinema listings. Booking happens on the official site.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  List<Show> _filterShows(List<Show> shows) => _formatFilter == null
      ? shows
      : [
          for (final s in shows)
            if (s.screenFormat == _formatFilter) s,
        ];
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        for (final c in children)
          Padding(padding: const EdgeInsets.only(right: 8), child: c),
      ],
    ),
  );
}

class _CinemaCard extends StatelessWidget {
  const _CinemaCard({
    required this.cinemaShows,
    required this.listingDate,
    required this.onShowTap,
  });

  final CinemaShows cinemaShows;
  final String listingDate;
  final void Function(Show) onShowTap;

  @override
  Widget build(BuildContext context) {
    final c = cinemaShows.cinema;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: theme.textTheme.titleSmall),
            if (c.isCancellable == true)
              Text('Cancellation available', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in cinemaShows.shows)
                  _ShowChip(
                    show: s,
                    listingDate: listingDate,
                    onTap: () => onShowTap(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowChip extends StatelessWidget {
  const _ShowChip({
    required this.show,
    required this.listingDate,
    required this.onTap,
  });

  final Show show;
  final String listingDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = show.availability.color(theme.colorScheme);
    final nextDay = !show.rawShowTime.startsWith(listingDate);
    final soldOut = show.availability == SeatAvailability.soldOut;
    return Semantics(
      button: true,
      label:
          '${Fmt.time(show.showTime)}${nextDay ? ' next day' : ''}, '
          '${show.screenFormat ?? ''}, ${show.seatsAvailable} seats left, '
          '${show.availability.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 170),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: Fmt.time(show.showTime),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      decoration: soldOut ? TextDecoration.lineThrough : null,
                    ),
                    children: [
                      if (nextDay)
                        TextSpan(
                          text: ' +1',
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                ),
                if (show.screenFormat != null || show.premiumLabel != null)
                  Text(
                    [?show.screenFormat, ?show.premiumLabel].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                Text(
                  soldOut ? 'Sold out' : '${show.seatsAvailable} left',
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

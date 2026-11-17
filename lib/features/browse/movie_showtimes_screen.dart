import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../app/widgets/availability.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/offline_banner.dart';
import '../../data/repo/showtime_repository.dart';
import '../../data/sources/showtime_source.dart';
import '../onboarding/city_controller.dart';
import '../show_detail/booking_launcher.dart';
import '../show_detail/show_detail_sheet.dart';
import 'browse_providers.dart';
import 'show_filter.dart';

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
  ShowFilter _filter = const ShowFilter();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(
          Uri(
            path: '/new-alert',
            queryParameters: {
              'id': '${widget.contentId}',
              'slug': widget.movieSlug,
              'name': cached?.value.movie.name ?? widget.title,
            },
          ).toString(),
        ),
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Alert me'),
      ),
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
          child: _body(
            context,
            c.value,
            offlineSince: c.offline ? c.fetchedAt : null,
          ),
        ),
      },
    );
  }

  Widget _body(
    BuildContext context,
    ShowtimesPage page, {
    DateTime? offlineSince,
  }) {
    final theme = Theme.of(context);
    final filtered = _filter.apply(page.cinemas);
    final showCount = filtered.fold<int>(0, (n, c) => n + c.shows.length);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (offlineSince != null) OfflineBanner(fetchedAt: offlineSince),
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
                    // Formats differ between languages; keep other filters.
                    _filter = _filter.copyWith(formats: {});
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
        _ChipRow(
          children: [
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: Text(
                _filter.isEmpty
                    ? 'Filters'
                    : 'Filters (${_filter.activeCount})',
              ),
              onPressed: () async {
                final next = await showModalBottomSheet<ShowFilter>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => ShowFilterSheet(page: page, initial: _filter),
                );
                if (next != null) setState(() => _filter = next);
              },
            ),
            for (final f in _filter.formats)
              InputChip(
                label: Text(f),
                onDeleted: () => setState(
                  () => _filter = _filter.copyWith(
                    formats: {..._filter.formats}..remove(f),
                  ),
                ),
              ),
            for (final c in _filter.chains)
              InputChip(
                label: Text(c),
                onDeleted: () => setState(
                  () => _filter = _filter.copyWith(
                    chains: {..._filter.chains}..remove(c),
                  ),
                ),
              ),
            for (final d in _filter.dayParts)
              InputChip(
                label: Text(d.label),
                onDeleted: () => setState(
                  () => _filter = _filter.copyWith(
                    dayParts: {..._filter.dayParts}..remove(d),
                  ),
                ),
              ),
            if (_filter.maxPrice case final max?)
              InputChip(
                label: Text('Up to ${Fmt.price(max)}'),
                onDeleted: () => setState(
                  () => _filter = _filter.copyWith(clearMaxPrice: true),
                ),
              ),
            if (_filter.hideSoldOut)
              InputChip(
                label: const Text('Hide sold out'),
                onDeleted: () => setState(
                  () => _filter = _filter.copyWith(hideSoldOut: false),
                ),
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
            child: Center(
              child: Text('No shows match this date and these filters.'),
            ),
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
}

/// Bottom sheet to edit a [ShowFilter] for the current page (FR-8).
class ShowFilterSheet extends StatefulWidget {
  const ShowFilterSheet({super.key, required this.page, required this.initial});

  final ShowtimesPage page;
  final ShowFilter initial;

  @override
  State<ShowFilterSheet> createState() => _ShowFilterSheetState();
}

class _ShowFilterSheetState extends State<ShowFilterSheet> {
  late ShowFilter _f = widget.initial;

  Set<T> _toggle<T>(Set<T> set, T v) =>
      set.contains(v) ? ({...set}..remove(v)) : {...set, v};

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final theme = Theme.of(context);
    final formats = <String>{
      for (final s in page.allShows) ?s.screenFormat,
    }.toList()..sort();
    final chains = <String>{
      for (final c in page.cinemas) ShowFilter.chainOf(c.cinema),
    }.toList()..sort();
    final prices = [for (final s in page.allShows) ?ShowFilter.cheapest(s)]
      ..sort();
    final low = prices.isEmpty ? 0.0 : prices.first.toDouble();
    final high = prices.isEmpty ? 0.0 : prices.last.toDouble();
    final matching = _f
        .apply(page.cinemas)
        .fold<int>(0, (n, c) => n + c.shows.length);

    Widget section(String title, List<Widget> chips) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        Wrap(spacing: 8, runSpacing: 4, children: chips),
      ],
    );

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (formats.length > 1)
                    section('Format', [
                      for (final f in formats)
                        FilterChip(
                          label: Text(f),
                          selected: _f.formats.contains(f),
                          onSelected: (_) => setState(
                            () => _f = _f.copyWith(
                              formats: _toggle(_f.formats, f),
                            ),
                          ),
                        ),
                    ]),
                  if (chains.length > 1)
                    section('Chain', [
                      for (final c in chains)
                        FilterChip(
                          label: Text(c),
                          selected: _f.chains.contains(c),
                          onSelected: (_) => setState(
                            () =>
                                _f = _f.copyWith(chains: _toggle(_f.chains, c)),
                          ),
                        ),
                    ]),
                  section('Time of day', [
                    for (final d in DayPart.values)
                      FilterChip(
                        label: Text('${d.label} (${d.range})'),
                        selected: _f.dayParts.contains(d),
                        onSelected: (_) => setState(
                          () => _f = _f.copyWith(
                            dayParts: _toggle(_f.dayParts, d),
                          ),
                        ),
                      ),
                  ]),
                  if (high > low) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _f.maxPrice == null
                            ? 'Max price: any'
                            : 'Max price: ${Fmt.price(_f.maxPrice!)} '
                                  '(cheapest seat)',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Slider(
                      min: low,
                      max: high,
                      divisions: ((high - low) / 10).ceil().clamp(1, 200),
                      value: (_f.maxPrice ?? high).toDouble().clamp(low, high),
                      label: Fmt.price((_f.maxPrice ?? high).round()),
                      onChanged: (v) => setState(
                        () => _f = v >= high
                            ? _f.copyWith(clearMaxPrice: true)
                            : _f.copyWith(maxPrice: v.round()),
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hide sold-out shows'),
                    value: _f.hideSoldOut,
                    onChanged: (v) =>
                        setState(() => _f = _f.copyWith(hideSoldOut: v)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _f = const ShowFilter()),
                    child: const Text('Clear all'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _f),
                    child: Text('Show $matching shows'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

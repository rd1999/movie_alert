import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../data/repo/showtime_repository.dart';
import '../browse/browse_providers.dart';
import '../onboarding/city_controller.dart';
import '../settings/settings_controller.dart';
import 'alert_text.dart';
import 'alerts_providers.dart';

enum AlertKind {
  cinema('Cinema opens', 'A cinema starts showing it'),
  format('Format opens', 'e.g. PXL, IMAX, 4DX, 3D'),
  date('Date opens', 'Bookings open for a date'),
  newCinema('Any new cinema', 'Any cinema not showing it today'),
  seats('Seats free up', 'A show has enough seats again');

  const AlertKind(this.title, this.hint);

  final String title;
  final String hint;
}

/// Create an alert for a condition that isn't true yet (FR-10..FR-13).
class CreateAlertScreen extends ConsumerStatefulWidget {
  const CreateAlertScreen({
    super.key,
    required this.contentId,
    required this.movieSlug,
    required this.movieName,
    this.initialCinemaId,
  });

  final int contentId;
  final String movieSlug;
  final String movieName;
  final int? initialCinemaId;

  @override
  ConsumerState<CreateAlertScreen> createState() => _CreateAlertScreenState();
}

class _CreateAlertScreenState extends ConsumerState<CreateAlertScreen> {
  static const intervals = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 6),
  ];
  static const formatSuggestions = [
    'PXL',
    'IMAX',
    '4DX',
    '3D',
    'LASER',
    'INSIGNIA',
  ];

  AlertKind _kind = AlertKind.cinema;
  final Map<int, String> _cinemas = {};
  final _format = TextEditingController();
  int _seats = 2;
  final Set<String> _dates = {};
  final Set<String> _groups = {};
  late Duration _interval = ref.read(settingsProvider).defaultInterval;
  bool _everyMatch = false;
  DateTime? _until;
  bool _untilTouched = false;
  bool _saving = false;

  @override
  void dispose() {
    _format.dispose();
    super.dispose();
  }

  ShowtimesQuery _defaultQuery(String cityKey) => (
    cityKey: cityKey,
    movieSlug: widget.movieSlug,
    contentId: widget.contentId,
    fmtGrpId: null,
    date: null,
  );

  /// Default end: start of the last wanted date (spec FR-13 suggests the day
  /// before the first date; the last date keeps later dates covered).
  DateTime? _defaultUntil() {
    if (_dates.isEmpty) return null;
    final last = (_dates.toList()..sort()).last;
    return DateTime.parse(last);
  }

  Set<int> get _cinemaIds => _cinemas.keys.toSet();

  AlertCondition _condition() => switch (_kind) {
    AlertKind.cinema => CinemaOpens(_cinemaIds),
    AlertKind.format => FormatOpens(_format.text.trim(), cinemaIds: _cinemaIds),
    AlertKind.date => DateOpens(cinemaIds: _cinemaIds),
    AlertKind.newCinema => const NewCinemaAnywhere(),
    AlertKind.seats => SeatsAvailable(_seats, cinemaIds: _cinemaIds),
  };

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(selectedCityProvider)!;
    final page = ref
        .watch(showtimesProvider(_defaultQuery(city.key)))
        .value
        ?.value;
    final cinemas = ref.watch(cinemasProvider(city.key));
    final theme = Theme.of(context);
    final showingNow = {
      for (final c in page?.cinemas ?? <CinemaShows>[]) c.cinema.id,
    };

    if (widget.initialCinemaId case final id? when _cinemas.isEmpty) {
      final name = [
        ...?cinemas.value?.value,
      ].where((c) => c.id == id).map((c) => c.name).firstOrNull;
      if (name != null) _cinemas[id] = name;
    }

    final cinemaRequired = _kind == AlertKind.cinema;
    final cinemaAllowed = _kind != AlertKind.newCinema;

    return Scaffold(
      appBar: AppBar(title: Text('Alert: ${widget.movieName}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Tell me when…', style: theme.textTheme.titleMedium),
          RadioGroup<AlertKind>(
            groupValue: _kind,
            onChanged: (k) => setState(() => _kind = k!),
            child: Column(
              children: [
                for (final k in AlertKind.values)
                  RadioListTile<AlertKind>(
                    value: k,
                    title: Text(k.title),
                    subtitle: Text(k.hint),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          if (_kind == AlertKind.format) ...[
            TextField(
              controller: _format,
              decoration: const InputDecoration(
                labelText: 'Format contains',
                hintText: 'PXL',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final f in {
                  ...formatSuggestions,
                  for (final s in page?.allShows ?? const <Show>[]) ...[
                    ?s.screenFormat,
                    ?s.premiumLabel,
                  ],
                })
                  ActionChip(
                    label: Text(f),
                    onPressed: () => setState(() => _format.text = f),
                  ),
              ],
            ),
          ],
          if (_kind == AlertKind.seats)
            Row(
              children: [
                const Text('At least'),
                IconButton(
                  onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$_seats', style: theme.textTheme.titleMedium),
                IconButton(
                  onPressed: () => setState(() => _seats++),
                  icon: const Icon(Icons.add),
                ),
                const Text('seats free'),
              ],
            ),
          if (cinemaAllowed) ...[
            const SizedBox(height: 16),
            _SectionTitle(
              cinemaRequired ? 'Cinemas' : 'Cinemas (optional, default: any)',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _cinemas.entries)
                  InputChip(
                    label: Text(e.value),
                    onDeleted: () => setState(() => _cinemas.remove(e.key)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Choose cinemas'),
                  onPressed: () async {
                    final list = cinemas.value?.value;
                    if (list == null) return;
                    final picked = await showModalBottomSheet<Map<int, String>>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _CinemaPicker(
                        cinemas: list,
                        showingNow: showingNow,
                        selected: Map.of(_cinemas),
                      ),
                    );
                    if (picked != null) {
                      setState(
                        () => _cinemas
                          ..clear()
                          ..addAll(picked),
                      );
                    }
                  },
                ),
              ],
            ),
            if (cinemas.hasError)
              Text(
                "Couldn't load the cinema list. Pull to refresh on Browse and "
                'try again.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
          const SizedBox(height: 16),
          _SectionTitle(
            _kind == AlertKind.date
                ? 'Dates'
                : 'Dates (optional, default: any)',
          ),
          _DatePickerRow(
            selected: _dates,
            bookable: {...?page?.sessionDates},
            onToggle: (d) => setState(() {
              _dates.contains(d) ? _dates.remove(d) : _dates.add(d);
              if (!_untilTouched) _until = _defaultUntil();
            }),
          ),
          if ((page?.languageFormats.length ?? 0) > 1) ...[
            const SizedBox(height: 16),
            const _SectionTitle('Languages (optional, default: all)'),
            Wrap(
              spacing: 8,
              children: [
                for (final g in page!.languageFormats)
                  FilterChip(
                    label: Text(g.language),
                    selected: _groups.contains(g.key),
                    onSelected: (on) => setState(
                      () => on ? _groups.add(g.key) : _groups.remove(g.key),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const _SectionTitle('Check every'),
          Wrap(
            spacing: 8,
            children: [
              for (final i in intervals)
                ChoiceChip(
                  label: Text(AlertText.interval(i)),
                  selected: _interval == i,
                  onSelected: (_) => setState(() => _interval = i),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep alerting on every new match'),
            subtitle: const Text(
              'Otherwise the alert stops after it fires once',
            ),
            value: _everyMatch,
            onChanged: (v) => setState(() => _everyMatch = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop checking on'),
            subtitle: Text(
              _until == null ? 'Never (until it fires)' : Fmt.day(_until!),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_until != null)
                  IconButton(
                    tooltip: 'No end date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _until = null;
                      _untilTouched = true;
                    }),
                  ),
                IconButton(
                  tooltip: 'Pick end date',
                  icon: const Icon(Icons.event),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: _until ?? now.add(const Duration(days: 7)),
                    );
                    if (d != null) {
                      setState(() {
                        _until = d;
                        _untilTouched = true;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          if (_interval < const Duration(minutes: 30))
            Text(
              'Short intervals use more data (~87 KB per page) and battery.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(city.key),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            label: const Text('Create alert'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(String cityKey) async {
    final alert = Alert(
      id: AlertsController.newId(),
      cityKey: cityKey,
      movieContentId: widget.contentId,
      movieSlug: widget.movieSlug,
      movieName: widget.movieName,
      condition: _condition(),
      createdAt: DateTime.now(),
      dates: {..._dates},
      fmtGrpIds: {..._groups},
      mode: _everyMatch ? AlertMode.everyNewMatch : AlertMode.once,
      interval: _interval,
      activeUntil: _until,
      cinemaNames: {..._cinemas},
    );
    final problems = alert.validate();
    final messenger = ScaffoldMessenger.of(context);
    if (problems.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(problems.join('\n'))));
      return;
    }
    // Ask before the spinner starts so the dialog isn't shown over it.
    final perms = ref.read(permissionsProvider);
    if (!await perms.notificationsGranted() && mounted) {
      final ask = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow notifications?'),
          content: const Text(
            'ShowWatch tells you about new shows with a notification. '
            'Without permission, the alert can only be seen in the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
      if (ask == true) await perms.requestNotifications();
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(alertsControllerProvider);
      await controller.save(alert);
      final summary = await controller.checkNow(alert.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            summary.fired > 0
                ? 'Already available! See the notification.'
                : summary.failed > 0
                ? "Alert saved, but the first check failed. We'll retry."
                : 'Alert set. Checking every ${AlertText.interval(_interval)}.',
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// The next 21 days as chips; dates already bookable get a dot.
class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.selected,
    required this.bookable,
    required this.onToggle,
  });

  final Set<String> selected;
  final Set<String> bookable;
  final void Function(String) onToggle;

  static String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final days = {
      for (var i = 0; i < 21; i++) ymd(start.add(Duration(days: i))),
      ...bookable,
      ...selected,
    }.toList()..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                showCheckmark: false,
                selected: selected.contains(d),
                onSelected: (_) => onToggle(d),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(Fmt.dateChip(d).$1),
                    Text(Fmt.dateChip(d).$2),
                    Text(
                      bookable.contains(d) ? '•' : ' ',
                      semanticsLabel: bookable.contains(d) ? 'bookable' : '',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Searchable multi-select over every cinema in the city.
class _CinemaPicker extends StatefulWidget {
  const _CinemaPicker({
    required this.cinemas,
    required this.showingNow,
    required this.selected,
  });

  final List<Cinema> cinemas;
  final Set<int> showingNow;
  final Map<int, String> selected;

  @override
  State<_CinemaPicker> createState() => _CinemaPickerState();
}

class _CinemaPickerState extends State<_CinemaPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final c in widget.cinemas)
        if (c.name.toLowerCase().contains(_q)) c,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search cinemas',
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in list)
                  CheckboxListTile(
                    value: widget.selected.containsKey(c.id),
                    title: Text(c.name),
                    subtitle: Text(
                      widget.showingNow.contains(c.id)
                          ? 'Showing this movie now'
                          : 'Not showing it yet',
                    ),
                    onChanged: (on) => setState(
                      () => on == true
                          ? widget.selected[c.id] = c.name
                          : widget.selected.remove(c.id),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, widget.selected),
                child: Text('Done (${widget.selected.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

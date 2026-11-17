import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../background/fast_mode_service.dart';
import '../../core/settings.dart';
import 'alerts_providers.dart';

final fastModeStateProvider = FutureProvider<FastModeState>(
  (ref) => ref.watch(fastModeProvider).state(),
);

/// Start/stop fast mode from the Alerts tab (FR-12).
class FastModeCard extends ConsumerWidget {
  const FastModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(fastModeProvider);
    if (!gateway.supported) return const SizedBox.shrink();
    final alerts = ref.watch(alertsProvider).value ?? const <Alert>[];
    final active = alerts.where((a) => a.status == AlertStatus.active).length;
    final state = ref.watch(fastModeStateProvider).value;
    final running = state?.isRunning(DateTime.now()) ?? false;
    final theme = Theme.of(context);

    if (running) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        color: theme.colorScheme.tertiaryContainer,
        child: ListTile(
          leading: const Icon(Icons.bolt),
          title: const Text('Fast mode is on'),
          subtitle: Text(
            'Checking every ${state!.interval?.inMinutes ?? '?'} min until '
            '${Fmt.time(state.endsAt!)}',
          ),
          trailing: TextButton(
            onPressed: () async {
              await gateway.stop();
              ref.invalidate(fastModeStateProvider);
            },
            child: const Text('Stop'),
          ),
        ),
      );
    }
    if (active == 0) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        leading: const Icon(Icons.bolt_outlined),
        title: const Text('Fast mode'),
        subtitle: const Text(
          'Check every few minutes for a while, e.g. when bookings are '
          'about to open',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final started = await showModalBottomSheet<bool>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => _FastModeSheet(
              activeAlerts: alerts
                  .where((a) => a.status == AlertStatus.active)
                  .toList(),
            ),
          );
          if (started == true) ref.invalidate(fastModeStateProvider);
        },
      ),
    );
  }
}

class _FastModeSheet extends ConsumerStatefulWidget {
  const _FastModeSheet({required this.activeAlerts});

  final List<Alert> activeAlerts;

  @override
  ConsumerState<_FastModeSheet> createState() => _FastModeSheetState();
}

class _FastModeSheetState extends ConsumerState<_FastModeSheet> {
  static const intervals = [
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];
  static const lengths = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 6),
  ];

  Duration _interval = const Duration(minutes: 5);
  Duration _length = const Duration(hours: 1);
  late final Future<Duration> _remaining = ref
      .read(fastModeProvider)
      .remainingToday();
  bool _starting = false;

  static String _len(Duration d) =>
      d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Each check fetches about two pages per movie being watched.
    final movies = {for (final a in widget.activeAlerts) a.movieContentId};
    final checks = _length.inMinutes ~/ _interval.inMinutes;
    final mb =
        checks * movies.length * 2 * DataUsage.bytesPerPage / (1024 * 1024);
    return SafeArea(
      child: FutureBuilder<Duration>(
        future: _remaining,
        builder: (context, snap) {
          final left = snap.data;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fast mode', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                  'Checks all active alerts every few minutes while a '
                  'notification is shown. Uses more battery and data.',
                ),
                const SizedBox(height: 12),
                Text('Check every', style: theme.textTheme.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final i in intervals)
                      ChoiceChip(
                        label: Text('${i.inMinutes} min'),
                        selected: _interval == i,
                        onSelected: (_) => setState(() => _interval = i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('For', style: theme.textTheme.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final l in lengths)
                      ChoiceChip(
                        label: Text(_len(l)),
                        selected: _length == l,
                        onSelected: left == null || l > left
                            ? null
                            : (_) => setState(() => _length = l),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '~$checks checks · ~${mb.toStringAsFixed(0)} MB · '
                  '${left == null ? '' : '${_len(left)} of fast mode left today'}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.bolt),
                    label: const Text('Start fast mode'),
                    onPressed: _starting || left == null || _length > left
                        ? null
                        : () async {
                            setState(() => _starting = true);
                            final nav = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
                                  .read(fastModeProvider)
                                  .start(interval: _interval, length: _length);
                              nav.pop(true);
                            } on StateError catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                              if (mounted) setState(() => _starting = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

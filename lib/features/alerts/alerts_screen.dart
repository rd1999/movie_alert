import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../app/widgets/error_view.dart';
import '../../background/alert_runner.dart';
import 'alert_text.dart';
import 'alerts_providers.dart';

/// Alert list with status, last/next check and "Check now" (FR-14).
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Background runs update the DB; re-read when the user comes back.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(alertsControllerProvider).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            tooltip: 'Alert setup',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/setup'),
          ),
        ],
      ),
      body: alerts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(alertsProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.read(alertsControllerProvider).refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _SetupBanner(),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No alerts yet.\n\nOpen a movie and tap "Alert me" to '
                    'watch for a cinema, format or date that isn\'t bookable '
                    'yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final a in list) _AlertCard(alert: a),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nudges the user to finish setup when notifications are off.
class _SetupBanner extends ConsumerWidget {
  const _SetupBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    if (!perms.backgroundAlertsSupported) {
      return const MaterialBanner(
        content: Text(
          'Background alerts are Android-only for now. On this device, use '
          '"Check now" or keep the app open.',
        ),
        actions: [SizedBox.shrink()],
      );
    }
    return FutureBuilder<bool>(
      future: perms.notificationsGranted(),
      builder: (context, snap) {
        if (snap.data != false) return const SizedBox.shrink();
        return MaterialBanner(
          leading: const Icon(Icons.notifications_off_outlined),
          content: const Text(
            'Notifications are off, so alerts can\'t reach you.',
          ),
          actions: [
            TextButton(
              onPressed: () => context.push('/setup'),
              child: const Text('Set up'),
            ),
          ],
        );
      },
    );
  }
}

class _AlertCard extends ConsumerStatefulWidget {
  const _AlertCard({required this.alert});

  final Alert alert;

  @override
  ConsumerState<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends ConsumerState<_AlertCard> {
  bool _checking = false;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = await ref
          .read(alertsControllerProvider)
          .checkNow(widget.alert.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.fired > 0
                ? 'Match found — see the notification.'
                : s.failed > 0
                ? 'Check failed. See history.'
                : 'Checked. No match yet.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final theme = Theme.of(context);
    final controller = ref.read(alertsControllerProvider);
    final next = AlertRunner.nextCheck(a);
    final statusColor = switch (a.status) {
      AlertStatus.active => theme.colorScheme.primary,
      AlertStatus.fired => const Color(0xFF2E7D32),
      AlertStatus.error => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };
    final lines = [
      AlertText.dates(a),
      'Every ${AlertText.interval(a.interval)}'
          '${a.mode == AlertMode.everyNewMatch ? ' · every new match' : ''}'
          '${a.activeUntil == null ? '' : ' · until ${Fmt.day(a.activeUntil!)}'}',
      [
        a.lastCheckedAt == null
            ? 'Not checked yet'
            : 'Checked ${Fmt.ago(a.lastCheckedAt!)}',
        if (next != null)
          next.isBefore(DateTime.now())
              ? 'next check soon'
              : 'next ~${Fmt.time(next)}',
        '${a.checkCount} checks',
      ].join(' · '),
      if (a.consecutiveFailures > 0)
        'Last ${a.consecutiveFailures} check(s) failed',
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        onTap: () => context.push('/alerts/${a.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      a.movieName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    AlertText.status(a.status),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              Text(AlertText.condition(a), style: theme.textTheme.bodyMedium),
              for (final l in lines) Text(l, style: theme.textTheme.bodySmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (a.status == AlertStatus.active)
                    TextButton.icon(
                      onPressed: _checking ? null : _checkNow,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Check now'),
                    ),
                  if (a.status == AlertStatus.active)
                    TextButton(
                      onPressed: () =>
                          controller.setStatus(a.id, AlertStatus.paused),
                      child: const Text('Pause'),
                    )
                  else
                    TextButton(
                      onPressed: () =>
                          controller.setStatus(a.id, AlertStatus.active),
                      child: Text(
                        a.status == AlertStatus.paused ? 'Resume' : 'Re-arm',
                      ),
                    ),
                  IconButton(
                    tooltip: 'Delete alert',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete this alert?'),
                          content: Text(AlertText.condition(a)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await controller.delete(a.id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

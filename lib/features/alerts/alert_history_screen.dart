import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/widgets/error_view.dart';
import '../../data/db/app_database.dart';
import 'alert_text.dart';
import 'alerts_providers.dart';

/// Every check of one alert, newest first (FR-15).
class AlertHistoryScreen extends ConsumerWidget {
  const AlertHistoryScreen({super.key, required this.alertId});

  final String alertId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(alertProvider(alertId));
    final logs = ref.watch(alertLogsProvider(alertId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(alert.value?.movieName ?? 'Alert')),
      body: switch ((alert, logs)) {
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => ErrorView(error: error),
        (AsyncData(value: null), _) => const Center(
          child: Text('This alert was deleted.'),
        ),
        (AsyncData(value: final a?), AsyncData(value: final entries)) =>
          ListView(
            children: [
              ListTile(
                title: Text(AlertText.condition(a)),
                subtitle: Text(
                  '${AlertText.dates(a)}\n'
                  '${AlertText.status(a.status)} · every '
                  '${AlertText.interval(a.interval)} · ${a.checkCount} checks',
                ),
                isThreeLine: true,
              ),
              const Divider(),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No checks yet.', textAlign: TextAlign.center),
                ),
              for (final e in entries)
                ListTile(
                  leading: Icon(
                    switch (e.outcome) {
                      CheckOutcome.ok => Icons.check_circle_outline,
                      CheckOutcome.fired => Icons.notifications_active,
                      CheckOutcome.failed => Icons.error_outline,
                      CheckOutcome.expired => Icons.timer_off_outlined,
                    },
                    color: switch (e.outcome) {
                      CheckOutcome.fired => const Color(0xFF2E7D32),
                      CheckOutcome.failed => theme.colorScheme.error,
                      _ => theme.colorScheme.outline,
                    },
                  ),
                  title: Text(
                    '${Fmt.day(e.at)} ${Fmt.time(e.at)} · ${e.outcome.name}',
                  ),
                  subtitle: Text(
                    [
                      ?e.message,
                      if (e.pagesFetched case final p?) '$p page(s) fetched',
                    ].join('\n'),
                  ),
                ),
            ],
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

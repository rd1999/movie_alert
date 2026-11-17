import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../alerts/alert_text.dart';
import '../alerts/alerts_providers.dart';
import 'settings_controller.dart';

/// Default interval, Wi-Fi only, alarm style, quiet hours, data limit and
/// data source status (FR-16, FR-20, FR-21).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const intervals = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 6),
  ];
  static const limits = [0, 10, 25, 50, 100];

  static String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final usage = ref.watch(dataUsageProvider).value;
    final alerts = ref.watch(alertsProvider).value ?? const <Alert>[];
    final lastOk = alerts
        .map((a) => a.lastCheckedAt)
        .nonNulls
        .fold<DateTime?>(null, (m, t) => m == null || t.isAfter(m) ? t : m);
    final theme = Theme.of(context);

    Future<void> pickTime(bool start) async {
      final current = start ? s.quietStartMinute : s.quietEndMinute;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      );
      if (t == null) return;
      final m = t.hour * 60 + t.minute;
      await controller.update(
        start ? s.copyWith(quietStartMinute: m) : s.copyWith(quietEndMinute: m),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Header('Alerts'),
          ListTile(
            title: const Text('Default check interval'),
            subtitle: Wrap(
              spacing: 8,
              children: [
                for (final i in intervals)
                  ChoiceChip(
                    label: Text(AlertText.interval(i)),
                    selected: s.defaultInterval == i,
                    onSelected: (_) =>
                        controller.update(s.copyWith(defaultInterval: i)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Alarm-style alerts'),
            subtitle: const Text(
              'Play alerts on the alarm stream so they ring on silent',
            ),
            value: s.alarmStyle,
            onChanged: (v) => controller.update(s.copyWith(alarmStyle: v)),
          ),
          SwitchListTile(
            title: const Text('Quiet hours'),
            subtitle: Text(
              s.quietHours
                  ? 'Alerts arrive without sound from '
                        '${_clock(s.quietStartMinute)} to ${_clock(s.quietEndMinute)}'
                  : 'Alerts always make a sound',
            ),
            value: s.quietHours,
            onChanged: (v) => controller.update(s.copyWith(quietHours: v)),
          ),
          if (s.quietHours)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () => pickTime(true),
                    child: Text('From ${_clock(s.quietStartMinute)}'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => pickTime(false),
                    child: Text('To ${_clock(s.quietEndMinute)}'),
                  ),
                ],
              ),
            ),
          const _Header('Data'),
          SwitchListTile(
            title: const Text('Background checks on Wi-Fi only'),
            subtitle: const Text(
              'Saves mobile data, but alerts wait until you are on Wi-Fi',
            ),
            value: s.wifiOnly,
            onChanged: (v) => controller.update(s.copyWith(wifiOnly: v)),
          ),
          ListTile(
            title: const Text('Daily data limit for background checks'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mb in limits)
                      ChoiceChip(
                        label: Text(mb == 0 ? 'No limit' : '$mb MB'),
                        selected: s.dailyDataLimitMb == mb,
                        onSelected: (_) =>
                            controller.update(s.copyWith(dailyDataLimitMb: mb)),
                      ),
                  ],
                ),
                if (usage != null)
                  Text(
                    'Today: ~${usage.megabytes.toStringAsFixed(1)} MB '
                    '(${usage.pages} pages, ~87 KB each)'
                    '${usage.overLimit(s) ? ' · limit reached, checks paused until tomorrow' : ''}',
                  ),
              ],
            ),
          ),
          const _Header('Data source'),
          ListTile(
            title: const Text('Public cinema listings'),
            subtitle: Text(
              'Parser v${DistrictParser.version} · last successful check: '
              '${lastOk == null ? 'none yet' : Fmt.ago(lastOk)}',
            ),
          ),
          ListTile(
            title: const Text('Alert setup'),
            subtitle: const Text(
              'Permissions, battery optimisation, test alert',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/setup'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'ShowWatch is not affiliated with any ticketing platform or '
              'cinema chain. It never books tickets or takes payments; it '
              'opens the official booking page. Checks are polite: at most '
              'one request per second, and background checks no more often '
              'than every 15 minutes (fast mode excepted).',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../background/worker_entrypoint.dart';
import '../../core/prefs/prefs.dart';
import '../alerts/alerts_providers.dart';
import '../show_detail/booking_launcher.dart';

/// Make background alerts reliable: permissions, battery optimisation,
/// OEM tips, alarm style, test alert, data source status
/// (FR-2, FR-3, FR-16, FR-21).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late Future<(bool, bool)> _status = _load();

  // The battery prompt is a system screen: re-check when the user is back.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _reload);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<(bool, bool)> _load() async {
    final p = ref.read(permissionsProvider);
    return (await p.notificationsGranted(), await p.batteryUnrestricted());
  }

  void _reload() => setState(() => _status = _load());

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    final prefs = ref.watch(sharedPrefsProvider);
    final alarmStyle = prefs.getBool(alarmStylePrefKey) ?? false;
    final alerts = ref.watch(alertsProvider).value ?? const <Alert>[];
    final lastOk = alerts
        .map((a) => a.lastCheckedAt)
        .nonNulls
        .fold<DateTime?>(null, (m, t) => m == null || t.isAfter(m) ? t : m);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Alert setup')),
      body: FutureBuilder<(bool, bool)>(
        future: _status,
        builder: (context, snap) {
          final (notifOk, batteryOk) = snap.data ?? (false, false);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (!perms.backgroundAlertsSupported)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Background alerts are Android-only for now'),
                  subtitle: Text(
                    'iOS decides when apps may run in the background, so '
                    'alerts there need a server (planned). Use "Check now" '
                    'on the Alerts tab.',
                  ),
                ),
              _StepTile(
                done: notifOk,
                title: 'Notifications',
                body:
                    'Alerts arrive as notifications. Without permission you '
                    'would only see them inside the app.',
                action: 'Allow',
                onAction: () async {
                  await perms.requestNotifications();
                  _reload();
                },
              ),
              if (perms.backgroundAlertsSupported)
                _StepTile(
                  done: batteryOk,
                  title: 'Battery optimisation',
                  body:
                      'Android may delay or skip background checks to save '
                      'battery. Let ShowWatch run unrestricted so alerts '
                      'arrive on time.',
                  action: 'Allow',
                  onAction: () async {
                    await perms.requestBatteryUnrestricted();
                    _reload();
                  },
                ),
              if (perms.backgroundAlertsSupported)
                ExpansionTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Phone-specific tips'),
                  subtitle: const Text('Xiaomi, Samsung, Oppo, Realme, Vivo…'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• Xiaomi / Redmi / POCO: Settings → Apps → ShowWatch → '
                      'Battery saver → No restrictions, and turn on Autostart.\n'
                      '• Samsung: Settings → Battery → Background usage limits '
                      '→ Never sleeping apps → add ShowWatch.\n'
                      '• Oppo / Realme / OnePlus: Settings → Battery → allow '
                      'background activity and auto launch for ShowWatch.\n'
                      '• Vivo: Settings → Battery → High background power '
                      'consumption → allow ShowWatch.\n'
                      '• Don\'t swipe ShowWatch away from recent apps on '
                      'phones that treat that as "force stop".',
                    ),
                    TextButton(
                      onPressed: () => openBooking(
                        context,
                        Uri.parse('https://dontkillmyapp.com/'),
                      ),
                      child: const Text('More at dontkillmyapp.com'),
                    ),
                  ],
                ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.alarm),
                title: const Text('Alarm-style alerts'),
                subtitle: const Text(
                  'Play alerts on the alarm stream so they ring even when '
                  'the phone is on silent',
                ),
                value: alarmStyle,
                onChanged: (v) async {
                  await prefs.setBool(alarmStylePrefKey, v);
                  ref.read(notificationServiceProvider).alarmStyle = v;
                  setState(() {});
                },
              ),
              if (perms.backgroundAlertsSupported)
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Send a test alert'),
                  subtitle: const Text(
                    'Arrives in about a minute through the background '
                    'scheduler. Lock the phone to check it gets through.',
                  ),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref
                        .read(backgroundSchedulerProvider)
                        .notifyLater(
                          uniqueName: 'test-alert',
                          delay: const Duration(minutes: 1),
                          title: 'ShowWatch test alert',
                          body: 'Background alerts work on this phone.',
                        );
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Test alert in ~1 minute')),
                    );
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Data source'),
                subtitle: Text(
                  'Public cinema listings · parser v${DistrictParser.version}\n'
                  'Last successful check: '
                  '${lastOk == null ? 'none yet' : Fmt.ago(lastOk)}',
                ),
                isThreeLine: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Checks are polite: at most one request per second, never '
                  'faster than every 15 minutes in the background.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.done,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final bool done;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      done ? Icons.check_circle : Icons.radio_button_unchecked,
      color: done ? const Color(0xFF2E7D32) : null,
    ),
    title: Text(title),
    subtitle: Text(body),
    isThreeLine: true,
    trailing: done
        ? const Text('Done')
        : FilledButton.tonal(onPressed: onAction, child: Text(action)),
  );
}

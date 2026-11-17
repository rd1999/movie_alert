import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db/app_database.dart';
import '../notifications/notification_service.dart';
import 'alert_runner.dart';
import 'scheduler.dart';

/// Pref key shared with Settings: play alerts on the alarm stream.
const alarmStylePrefKey = 'alerts.alarmStyle';

/// Registers [callbackDispatcher] with WorkManager. Safe to call repeatedly.
Future<void> initBackgroundWork() =>
    Workmanager().initialize(callbackDispatcher);

/// Background isolate entry point: load alerts -> fetch -> evaluate ->
/// notify -> persist (spec §10.1).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = await NotificationService.init(
        alarmStyle: prefs.getBool(alarmStylePrefKey) ?? false,
      );
      switch (task) {
        case BackgroundTasks.checkAlerts:
          final fetcher = PoliteFetcher();
          try {
            final summary = await AlertRunner(
              store: await SqfliteAlertStore.open(),
              source: DistrictSource(fetcher.get),
              notifier: notifications,
            ).run();
            debugPrint('ShowWatch background run: $summary');
          } finally {
            fetcher.close();
          }
        case BackgroundTasks.notify:
          await notifications.showPlain(
            title: input?['title'] as String? ?? 'ShowWatch',
            body: input?['body'] as String? ?? '',
            payload: input?['payload'] as String?,
          );
      }
    } catch (e, s) {
      // Failures are recorded per alert by the runner. Returning true keeps
      // WorkManager from piling extra retries on top of the schedule (NFR-1).
      debugPrint('ShowWatch background task $task failed: $e\n$s');
    }
    return true;
  });
}

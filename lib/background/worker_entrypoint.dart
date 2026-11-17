import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';
import 'package:workmanager/workmanager.dart';

import '../core/settings.dart';
import '../data/db/app_database.dart';
import '../notifications/notification_service.dart';
import 'alert_runner.dart';
import 'scheduler.dart';

/// Registers [callbackDispatcher] with WorkManager. Safe to call repeatedly.
Future<void> initBackgroundWork() =>
    Workmanager().initialize(callbackDispatcher);

/// Runs due alerts from a background context (WorkManager, fast mode),
/// respecting the daily data limit (FR-20) and recording data used.
/// Returns null when skipped because of the limit.
Future<RunSummary?> runAlertsInBackground({bool force = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // The UI isolate may have changed settings.
  final settings = AppSettings.read(prefs);
  final now = DateTime.now();
  if (DataUsage.read(prefs, now).overLimit(settings)) {
    debugPrint('ShowWatch: daily data limit reached, skipping run');
    return null;
  }
  final notifications = await NotificationService.init(settings: settings);
  final fetcher = PoliteFetcher();
  try {
    final summary = await AlertRunner(
      store: await SqfliteAlertStore.open(),
      source: DistrictSource(fetcher.get),
      notifier: notifications,
    ).run(force: force);
    await DataUsage.add(prefs, now, summary.pagesFetched);
    return summary;
  } finally {
    fetcher.close();
  }
}

/// Background isolate entry point: load alerts -> fetch -> evaluate ->
/// notify -> persist (spec §10.1).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      switch (task) {
        case BackgroundTasks.checkAlerts:
          final summary = await runAlertsInBackground();
          debugPrint('ShowWatch background run: $summary');
        case BackgroundTasks.notify:
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final notifications = await NotificationService.init(
            settings: AppSettings.read(prefs),
          );
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

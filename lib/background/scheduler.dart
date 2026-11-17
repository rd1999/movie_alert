import 'package:showtime_core/showtime_core.dart';
import 'package:workmanager/workmanager.dart';

/// Background scheduling, behind an interface so the UI can be tested.
abstract interface class BackgroundScheduler {
  /// Makes sure the periodic check runs as often as the most frequent active
  /// alert needs (>= 15 min), or not at all when nothing is active.
  Future<void> sync(List<Alert> alerts);

  /// Shows a plain notification after [delay] (snooze, "Test alert").
  Future<void> notifyLater({
    required String uniqueName,
    required Duration delay,
    required String title,
    required String body,
    String? payload,
  });
}

abstract final class BackgroundTasks {
  static const checkAlerts = 'showwatch.checkAlerts';
  static const notify = 'showwatch.notify';
  static const periodicName = 'showwatch.periodic-check';

  /// Android's WorkManager floor for periodic work (spec §4).
  static const minPeriod = Duration(minutes: 15);
}

/// One shared periodic task rather than one per alert: every run checks all
/// due alerts together, so each page is fetched once (FR-19).
class WorkmanagerScheduler implements BackgroundScheduler {
  const WorkmanagerScheduler();

  static Duration periodFor(List<Alert> alerts) {
    final intervals = [
      for (final a in alerts)
        if (a.status == AlertStatus.active) a.interval,
    ];
    final shortest = intervals.reduce((a, b) => a < b ? a : b);
    return shortest < BackgroundTasks.minPeriod
        ? BackgroundTasks.minPeriod
        : shortest;
  }

  @override
  Future<void> sync(List<Alert> alerts) async {
    if (!alerts.any((a) => a.status == AlertStatus.active)) {
      await Workmanager().cancelByUniqueName(BackgroundTasks.periodicName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      BackgroundTasks.periodicName,
      BackgroundTasks.checkAlerts,
      frequency: periodFor(alerts),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> notifyLater({
    required String uniqueName,
    required Duration delay,
    required String title,
    required String body,
    String? payload,
  }) => Workmanager().registerOneOffTask(
    uniqueName,
    BackgroundTasks.notify,
    initialDelay: delay,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    inputData: {'title': title, 'body': body, 'payload': ?payload},
  );
}

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../background/alert_runner.dart';
import '../../background/scheduler.dart';
import '../../data/db/app_database.dart';
import '../../data/sources/showtime_source.dart';
import '../../notifications/notification_service.dart';
import '../../notifications/permissions.dart';

/// Overridden in `main()` with the opened database.
final alertStoreProvider = Provider<AlertStore>(
  (ref) => throw UnimplementedError('alertStoreProvider must be overridden'),
);

/// Overridden in `main()` with the initialised service.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider must be overridden',
  ),
);

final alertNotifierProvider = Provider<AlertNotifier>(
  (ref) => ref.watch(notificationServiceProvider),
);

final permissionsProvider = Provider<PermissionsGateway>(
  (ref) => DevicePermissions(ref.watch(notificationServiceProvider)),
);

final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
  (ref) => const WorkmanagerScheduler(),
);

final alertsProvider = FutureProvider<List<Alert>>(
  (ref) => ref.watch(alertStoreProvider).alerts(),
);

final alertProvider = FutureProvider.family<Alert?, String>(
  (ref, id) => ref.watch(alertStoreProvider).alert(id),
);

final alertLogsProvider = FutureProvider.family<List<CheckLogEntry>, String>(
  (ref, id) => ref.watch(alertStoreProvider).logs(id),
);

/// All alert mutations go through here so the background schedule and the
/// UI stay in sync.
class AlertsController {
  AlertsController(this._ref);

  final Ref _ref;

  AlertStore get _store => _ref.read(alertStoreProvider);

  static String newId() {
    final r = Random.secure().nextInt(1 << 30).toRadixString(36);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$r';
  }

  Future<void> save(Alert alert) async {
    await _store.saveAlert(alert);
    await _changed(alert.id);
  }

  Future<void> setStatus(String id, AlertStatus status) async {
    final a = await _store.alert(id);
    if (a == null) return;
    await _store.saveAlert(
      a.copyWith(
        status: status,
        consecutiveFailures: status == AlertStatus.active ? 0 : null,
      ),
    );
    await _changed(id);
  }

  Future<void> delete(String id) async {
    await _store.deleteAlert(id);
    await _changed(id);
  }

  /// "Check now" (FR-14): one forced check for this alert, in the app.
  Future<RunSummary> checkNow(String id) async {
    final summary = await AlertRunner(
      store: _store,
      source: _ref.read(showtimeSourceProvider),
      notifier: _ref.read(alertNotifierProvider),
    ).run(onlyIds: {id}, force: true);
    await _changed(id);
    return summary;
  }

  /// Re-reads alerts (e.g. after a background run) and re-syncs the schedule.
  Future<void> refresh() => _changed(null);

  Future<void> _changed(String? id) async {
    final alerts = await _store.alerts();
    try {
      await _ref.read(backgroundSchedulerProvider).sync(alerts);
    } catch (_) {
      // No WorkManager (iOS, tests): checks still run via "Check now".
    }
    _ref.invalidate(alertsProvider);
    if (id != null) {
      _ref.invalidate(alertProvider(id));
      _ref.invalidate(alertLogsProvider(id));
    }
  }
}

final alertsControllerProvider = Provider<AlertsController>(
  AlertsController.new,
);

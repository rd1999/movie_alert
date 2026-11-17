import 'package:movie_alert/data/db/app_database.dart';
import 'package:showtime_core/showtime_core.dart';

/// In-memory [AlertStore] for tests.
class MemoryAlertStore implements AlertStore {
  final Map<String, Alert> byId = {};
  final List<CheckLogEntry> log = [];
  final Map<String, Snapshot> snapshots = {};

  /// Called inside [alert] lookups; lets tests simulate concurrent edits.
  void Function(String id)? onRead;

  @override
  Future<List<Alert>> alerts() async => byId.values.toList();

  @override
  Future<Alert?> alert(String id) async {
    onRead?.call(id);
    return byId[id];
  }

  @override
  Future<void> saveAlert(Alert alert) async => byId[alert.id] = alert;

  @override
  Future<void> deleteAlert(String id) async {
    byId.remove(id);
    log.removeWhere((e) => e.alertId == id);
  }

  @override
  Future<void> addLog(CheckLogEntry entry) async => log.add(entry);

  @override
  Future<List<CheckLogEntry>> logs(String alertId, {int limit = 100}) async => [
    for (final e in log.reversed)
      if (e.alertId == alertId) e,
  ].take(limit).toList();

  @override
  Future<void> saveSnapshot(String cityKey, int contentId, Snapshot s) async =>
      snapshots['$cityKey:$contentId'] = s;

  @override
  Future<Snapshot?> snapshot(String cityKey, int contentId) async =>
      snapshots['$cityKey:$contentId'];
}

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:showtime_core/showtime_core.dart';
import 'package:sqflite/sqflite.dart';

enum CheckOutcome { ok, fired, failed, expired }

/// One line of an alert's check history (FR-15).
class CheckLogEntry {
  const CheckLogEntry({
    required this.alertId,
    required this.at,
    required this.outcome,
    this.message,
    this.pagesFetched,
  });

  final String alertId;
  final DateTime at;
  final CheckOutcome outcome;
  final String? message;
  final int? pagesFetched;
}

/// Persistence for alerts, their check history and the latest snapshot per
/// (city, movie). Used from both the UI and the background isolate.
abstract interface class AlertStore {
  Future<List<Alert>> alerts();
  Future<Alert?> alert(String id);
  Future<void> saveAlert(Alert alert);
  Future<void> deleteAlert(String id);

  Future<void> addLog(CheckLogEntry entry);
  Future<List<CheckLogEntry>> logs(String alertId, {int limit = 100});

  Future<void> saveSnapshot(String cityKey, int contentId, Snapshot snapshot);
  Future<Snapshot?> snapshot(String cityKey, int contentId);
}

/// SQLite-backed [AlertStore]. Alerts and snapshots are stored as JSON from
/// the core models, so the schema stays tiny and the core package stays the
/// single source of truth for their shape.
class SqfliteAlertStore implements AlertStore {
  SqfliteAlertStore._(this._db);

  final Database _db;

  /// Max history rows kept per alert.
  static const logLimitPerAlert = 200;

  static Future<SqfliteAlertStore> open({String name = 'showwatch.db'}) async {
    final path = p.join(await getDatabasesPath(), name);
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE alerts (
            id TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE check_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            alert_id TEXT NOT NULL,
            at INTEGER NOT NULL,
            outcome TEXT NOT NULL,
            message TEXT,
            pages INTEGER
          )''');
        await db.execute(
          'CREATE INDEX check_log_alert ON check_log(alert_id, at DESC)',
        );
        await db.execute('''
          CREATE TABLE snapshots (
            key TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            taken_at INTEGER NOT NULL
          )''');
      },
    );
    return SqfliteAlertStore._(db);
  }

  static Alert _decode(Object? json) =>
      Alert.fromJson(jsonDecode(json as String) as Map<String, Object?>);

  @override
  Future<List<Alert>> alerts() async {
    final rows = await _db.query('alerts', orderBy: 'created_at DESC');
    return [for (final r in rows) _decode(r['json'])];
  }

  @override
  Future<Alert?> alert(String id) async {
    final rows = await _db.query('alerts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _decode(rows.single['json']);
  }

  @override
  Future<void> saveAlert(Alert alert) => _db.insert('alerts', {
    'id': alert.id,
    'json': jsonEncode(alert.toJson()),
    'created_at': alert.createdAt.millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> deleteAlert(String id) => _db.transaction((txn) async {
    await txn.delete('alerts', where: 'id = ?', whereArgs: [id]);
    await txn.delete('check_log', where: 'alert_id = ?', whereArgs: [id]);
  });

  @override
  Future<void> addLog(CheckLogEntry e) => _db.transaction((txn) async {
    await txn.insert('check_log', {
      'alert_id': e.alertId,
      'at': e.at.millisecondsSinceEpoch,
      'outcome': e.outcome.name,
      'message': e.message,
      'pages': e.pagesFetched,
    });
    await txn.rawDelete(
      '''DELETE FROM check_log WHERE alert_id = ? AND id NOT IN (
           SELECT id FROM check_log WHERE alert_id = ?
           ORDER BY at DESC, id DESC LIMIT ?)''',
      [e.alertId, e.alertId, logLimitPerAlert],
    );
  });

  @override
  Future<List<CheckLogEntry>> logs(String alertId, {int limit = 100}) async {
    final rows = await _db.query(
      'check_log',
      where: 'alert_id = ?',
      whereArgs: [alertId],
      orderBy: 'at DESC, id DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        CheckLogEntry(
          alertId: alertId,
          at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
          outcome: CheckOutcome.values.byName(r['outcome'] as String),
          message: r['message'] as String?,
          pagesFetched: r['pages'] as int?,
        ),
    ];
  }

  @override
  Future<void> saveSnapshot(String cityKey, int contentId, Snapshot s) =>
      _db.insert('snapshots', {
        'key': '$cityKey:$contentId',
        'json': jsonEncode(s.toJson()),
        'taken_at': s.takenAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<Snapshot?> snapshot(String cityKey, int contentId) async {
    final rows = await _db.query(
      'snapshots',
      where: 'key = ?',
      whereArgs: ['$cityKey:$contentId'],
    );
    if (rows.isEmpty) return null;
    return Snapshot.fromJson(
      jsonDecode(rows.single['json'] as String) as Map<String, Object?>,
    );
  }
}

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/format.dart';
import 'worker_entrypoint.dart';

/// Fast mode (FR-12): an opt-in Android foreground service that checks all
/// active alerts every 2/5/10 minutes for a limited window, shown as a
/// persistent notification. Android 15 caps `dataSync` services at 6 h per
/// 24 h, so the app keeps its own 6 h/day budget (spec §4).
class FastModeState {
  const FastModeState({this.endsAt, this.interval});

  final DateTime? endsAt;
  final Duration? interval;

  bool isRunning(DateTime now) => endsAt != null && now.isBefore(endsAt!);
}

/// Daily fast-mode budget, stored in prefs. Starting reserves the chosen
/// duration; stopping early refunds what wasn't used.
class FastModeBudget {
  static const daily = Duration(hours: 6);
  static const _kDay = 'fastmode.day';
  static const _kUsed = 'fastmode.usedMinutes';
  static const kEndsAt = 'fastmode.endsAt';
  static const kInterval = 'fastmode.intervalSeconds';

  static String _day(DateTime t) => '${t.year}-${t.month}-${t.day}';

  static Duration used(SharedPreferences p, DateTime now) =>
      p.getString(_kDay) == _day(now)
      ? Duration(minutes: p.getInt(_kUsed) ?? 0)
      : Duration.zero;

  static Duration remaining(SharedPreferences p, DateTime now) {
    final left = daily - used(p, now);
    return left.isNegative ? Duration.zero : left;
  }

  static Future<void> reserve(
    SharedPreferences p,
    DateTime now,
    Duration d,
  ) async {
    await p.setString(_kDay, _day(now));
    await p.setInt(_kUsed, (used(p, now) + d).inMinutes);
  }

  static Future<void> refund(
    SharedPreferences p,
    DateTime now,
    Duration d,
  ) async {
    if (d <= Duration.zero || p.getString(_kDay) != _day(now)) return;
    final left = used(p, now) - d;
    await p.setInt(_kUsed, left.isNegative ? 0 : left.inMinutes);
  }

  static FastModeState state(SharedPreferences p) {
    final ends = p.getInt(kEndsAt);
    final secs = p.getInt(kInterval);
    return FastModeState(
      endsAt: ends == null ? null : DateTime.fromMillisecondsSinceEpoch(ends),
      interval: secs == null ? null : Duration(seconds: secs),
    );
  }

  static Future<void> clear(SharedPreferences p) async {
    await p.remove(kEndsAt);
    await p.remove(kInterval);
  }
}

/// Behind an interface so the UI can be tested without the plugin.
abstract interface class FastModeGateway {
  bool get supported;
  Future<FastModeState> state();
  Future<Duration> remainingToday();

  /// Throws [StateError] with a user-facing message on failure.
  Future<void> start({required Duration interval, required Duration length});
  Future<void> stop();
}

class AndroidFastMode implements FastModeGateway {
  const AndroidFastMode();

  static const _serviceId = 4242;

  @override
  bool get supported => Platform.isAndroid;

  Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload(); // The service isolate writes these too.
    return p;
  }

  @override
  Future<FastModeState> state() async {
    final p = await _prefs();
    final s = FastModeBudget.state(p);
    if (s.isRunning(DateTime.now()) &&
        !await FlutterForegroundTask.isRunningService) {
      await FastModeBudget.clear(p); // Killed by the system.
      return const FastModeState();
    }
    return s;
  }

  @override
  Future<Duration> remainingToday() async =>
      FastModeBudget.remaining(await _prefs(), DateTime.now());

  @override
  Future<void> start({
    required Duration interval,
    required Duration length,
  }) async {
    final p = await _prefs();
    final now = DateTime.now();
    final left = FastModeBudget.remaining(p, now);
    if (length > left) {
      throw StateError(
        'Only ${left.inMinutes} min of fast mode left today (6 h per day).',
      );
    }
    final endsAt = now.add(length);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fast_mode',
        channelName: 'Fast mode',
        channelDescription: 'Shown while fast mode checks every few minutes',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(interval.inMilliseconds),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    await p.setInt(FastModeBudget.kEndsAt, endsAt.millisecondsSinceEpoch);
    await p.setInt(FastModeBudget.kInterval, interval.inSeconds);
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'ShowWatch fast mode',
      notificationText:
          'Checking every ${interval.inMinutes} min until ${Fmt.time(endsAt)}',
      notificationButtons: const [NotificationButton(id: 'stop', text: 'Stop')],
      callback: fastModeStartCallback,
    );
    if (result is ServiceRequestFailure) {
      await FastModeBudget.clear(p);
      throw StateError("Couldn't start fast mode: ${result.error}");
    }
    await FastModeBudget.reserve(p, now, length);
  }

  @override
  Future<void> stop() async {
    final p = await _prefs();
    final s = FastModeBudget.state(p);
    final now = DateTime.now();
    if (s.endsAt case final ends? when ends.isAfter(now)) {
      await FastModeBudget.refund(p, now, ends.difference(now));
    }
    await FastModeBudget.clear(p);
    await FlutterForegroundTask.stopService();
  }
}

final fastModeProvider = Provider<FastModeGateway>(
  (ref) => const AndroidFastMode(),
);

/// Service isolate entry point.
@pragma('vm:entry-point')
void fastModeStartCallback() {
  FlutterForegroundTask.setTaskHandler(_FastModeHandler());
}

class _FastModeHandler extends TaskHandler {
  bool _busy = false;

  Future<DateTime?> _endsAt() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return FastModeBudget.state(p).endsAt;
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _tick();

  @override
  void onRepeatEvent(DateTime timestamp) => _tick();

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final ends = await _endsAt();
      final now = DateTime.now();
      if (ends == null || !now.isBefore(ends)) {
        await FlutterForegroundTask.stopService();
        return;
      }
      final summary = await runAlertsInBackground(force: true);
      final last = Fmt.time(DateTime.now());
      await FlutterForegroundTask.updateService(
        notificationText: switch (summary) {
          null => 'Paused: daily data limit reached',
          final s when s.wasSkipped =>
            'Last check $last (another check was running) · until ${Fmt.time(ends)}',
          final s =>
            'Last check $last · ${s.checked} alert(s) · until ${Fmt.time(ends)}',
        },
      );
    } catch (e) {
      debugPrint('ShowWatch fast mode tick failed: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Stopped by the user, the end time or Android's dataSync timeout.
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final s = FastModeBudget.state(p);
    final now = DateTime.now();
    if (s.endsAt case final ends? when ends.isAfter(now)) {
      await FastModeBudget.refund(p, now, ends.difference(now));
    }
    await FastModeBudget.clear(p);
  }
}

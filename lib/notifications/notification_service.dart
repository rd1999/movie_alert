import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:showtime_core/showtime_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../background/alert_runner.dart';
import '../background/scheduler.dart';
import '../background/worker_entrypoint.dart';
import '../data/db/app_database.dart';

/// Payload carried by alert notifications (JSON string).
class AlertPayload {
  const AlertPayload({this.alertId, this.url, this.title, this.body});

  final String? alertId;
  final String? url;
  final String? title;
  final String? body;

  String encode() => jsonEncode({
    'alertId': ?alertId,
    'url': ?url,
    'title': ?title,
    'body': ?body,
  });

  static AlertPayload decode(String? s) {
    if (s == null || s.isEmpty) return const AlertPayload();
    try {
      final j = jsonDecode(s) as Map<String, Object?>;
      return AlertPayload(
        alertId: j['alertId'] as String?,
        url: j['url'] as String?,
        title: j['title'] as String?,
        body: j['body'] as String?,
      );
    } on FormatException {
      return const AlertPayload();
    }
  }
}

abstract final class NotificationActions {
  static const open = 'open';
  static const snooze = 'snooze';
  static const stop = 'stop';
}

/// Notifications for alerts (FR-16, FR-18). Usable from the UI isolate and
/// from background isolates (WorkManager).
class NotificationService implements AlertNotifier {
  NotificationService._(this._plugin, {required this.alarmStyle});

  final FlutterLocalNotificationsPlugin _plugin;

  /// Use the alarm channel (alarm audio stream, alarm category).
  bool alarmStyle;

  static const _alerts = AndroidNotificationChannel(
    'alerts',
    'Booking alerts',
    description: 'A cinema, format or date you watch opened for booking',
    importance: Importance.max,
  );

  static const _alarm = AndroidNotificationChannel(
    'alerts_alarm',
    'Booking alerts (alarm style)',
    description: 'Same alerts, played on the alarm stream',
    importance: Importance.max,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  static const _status = AndroidNotificationChannel(
    'status',
    'Alert problems',
    description: "An alert can't check for shows",
  );

  static Future<NotificationService> init({bool alarmStyle = false}) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: handleNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final c in [_alerts, _alarm, _status]) {
      await android?.createNotificationChannel(c);
    }
    return NotificationService._(plugin, alarmStyle: alarmStyle);
  }

  /// Android 13+ runtime permission (FR-2). True when granted.
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  /// Whether notifications are allowed (Android 13+ permission / settings).
  Future<bool> notificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final perms = await ios?.checkPermissions();
    return perms?.isEnabled ?? false;
  }

  /// Stable notification id per alert (newer matches replace older ones).
  static int idFor(String alertId) {
    var h = 0x811c9dc5;
    for (final c in alertId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  @override
  Future<void> alertFired(Alert alert, AlertEvent event, Uri bookingUrl) {
    final body = event.body();
    final channel = alarmStyle ? _alarm : _alerts;
    return _plugin.show(
      id: idFor(alert.id),
      title: event.title,
      body: body,
      payload: AlertPayload(
        alertId: alert.id,
        url: bookingUrl.toString(),
        title: event.title,
        body: body,
      ).encode(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          category: alarmStyle
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.reminder,
          audioAttributesUsage: alarmStyle
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          styleInformation: BigTextStyleInformation(body),
          ticker: event.title,
          actions: const [
            AndroidNotificationAction(
              NotificationActions.open,
              'Open booking',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              NotificationActions.snooze,
              'Snooze 10 min',
            ),
            AndroidNotificationAction(NotificationActions.stop, 'Stop alert'),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> alertFailing(Alert alert, Object error) => _plugin.show(
    id: idFor('status:${alert.id}'),
    title: "${alert.movieName}: alert can't check",
    body: '${describeCheckError(error)}. Open ShowWatch to fix it.',
    payload: AlertPayload(alertId: alert.id).encode(),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _status.id,
        _status.name,
        channelDescription: _status.description,
      ),
    ),
  );

  /// Plain notification (snooze re-show, "Test alert").
  Future<void> showPlain({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) {
    final channel = alarmStyle ? _alarm : _alerts;
    return _plugin.show(
      id: id ?? idFor('plain:$title'),
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          audioAttributesUsage: alarmStyle
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  /// If the app was launched by tapping a notification, handle it.
  Future<void> handleLaunchDetails() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true && response != null) {
      await handleNotificationTap(response);
    }
  }
}

/// Tap on a notification or on a button that opens the app.
@pragma('vm:entry-point')
Future<void> handleNotificationTap(NotificationResponse r) async {
  final payload = AlertPayload.decode(r.payload);
  switch (r.actionId) {
    case NotificationActions.snooze || NotificationActions.stop:
      await notificationBackgroundHandler(r);
    default:
      final url = payload.url;
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
  }
}

/// Buttons that don't open the app run here, in a background isolate.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  final payload = AlertPayload.decode(r.payload);
  try {
    switch (r.actionId) {
      case NotificationActions.stop:
        final id = payload.alertId;
        if (id == null) return;
        final store = await SqfliteAlertStore.open();
        final alert = await store.alert(id);
        if (alert != null && alert.status == AlertStatus.active) {
          await store.saveAlert(alert.copyWith(status: AlertStatus.paused));
          await store.addLog(
            CheckLogEntry(
              alertId: id,
              at: DateTime.now(),
              outcome: CheckOutcome.ok,
              message: 'Stopped from the notification',
            ),
          );
        }
      case NotificationActions.snooze:
        await initBackgroundWork();
        await const WorkmanagerScheduler().notifyLater(
          uniqueName: 'snooze:${payload.alertId}',
          delay: const Duration(minutes: 10),
          title: payload.title ?? 'ShowWatch',
          body: payload.body ?? '',
          payload: r.payload,
        );
    }
  } catch (e, s) {
    debugPrint('notification action failed: $e\n$s');
  }
}

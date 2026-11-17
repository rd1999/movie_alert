import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/app/app.dart';
import 'package:movie_alert/background/alert_runner.dart';
import 'package:movie_alert/background/scheduler.dart';
import 'package:movie_alert/core/prefs/prefs.dart';
import 'package:movie_alert/data/sources/showtime_source.dart';
import 'package:movie_alert/features/alerts/alerts_providers.dart';
import 'package:movie_alert/notifications/permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/showtime_core.dart';

import 'fake_source.dart';
import 'memory_store.dart';

class FakeScheduler implements BackgroundScheduler {
  final synced = <List<Alert>>[];
  final later = <String>[];

  @override
  Future<void> sync(List<Alert> alerts, {bool wifiOnly = false}) async {
    synced.add(alerts);
    lastWifiOnly = wifiOnly;
  }

  bool? lastWifiOnly;

  @override
  Future<void> notifyLater({
    required String uniqueName,
    required Duration delay,
    required String title,
    required String body,
    String? payload,
  }) async => later.add(uniqueName);
}

class FakeNotifier implements AlertNotifier {
  final fired = <AlertEvent>[];

  @override
  Future<void> alertFired(Alert a, AlertEvent e, Uri url) async => fired.add(e);

  @override
  Future<void> alertFailing(Alert a, Object error) async {}
}

class FakePermissions implements PermissionsGateway {
  FakePermissions({this.granted = true});

  bool granted;
  int requests = 0;

  @override
  bool get backgroundAlertsSupported => true;

  @override
  Future<bool> notificationsGranted() async => granted;

  @override
  Future<bool> requestNotifications() async {
    requests++;
    return granted = true;
  }

  @override
  Future<bool> batteryUnrestricted() async => true;

  @override
  Future<void> requestBatteryUnrestricted() async {}
}

class TestApp {
  TestApp({
    FakeSource? source,
    MemoryAlertStore? store,
    FakePermissions? permissions,
  }) : source = source ?? FakeSource(),
       store = store ?? MemoryAlertStore(),
       permissions = permissions ?? FakePermissions();

  final FakeSource source;
  final MemoryAlertStore store;
  final FakePermissions permissions;
  final scheduler = FakeScheduler();
  final notifier = FakeNotifier();

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          showtimeSourceProvider.overrideWithValue(source),
          alertStoreProvider.overrideWithValue(store),
          backgroundSchedulerProvider.overrideWithValue(scheduler),
          alertNotifierProvider.overrideWithValue(notifier),
          permissionsProvider.overrideWithValue(permissions),
          notificationSettingsSinkProvider.overrideWithValue((_) {}),
        ],
        retry: (_, _) => null,
        child: const ShowWatchApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'background/scheduler.dart';
import 'background/worker_entrypoint.dart';
import 'core/prefs/prefs.dart';
import 'data/db/app_database.dart';
import 'data/repo/showtime_repository.dart';
import 'features/alerts/alerts_providers.dart';
import 'notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final store = await SqfliteAlertStore.open();
  final notifications = await NotificationService.init(
    alarmStyle: prefs.getBool(alarmStylePrefKey) ?? false,
  );
  if (Platform.isAndroid) {
    try {
      await initBackgroundWork();
      // Re-assert the schedule on every launch (e.g. after an app update).
      await const WorkmanagerScheduler().sync(await store.alerts());
    } catch (e) {
      debugPrint('Background scheduling unavailable: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        alertStoreProvider.overrideWithValue(store),
        pageCacheProvider.overrideWithValue(store),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      // No automatic retries: every request to the listings site is
      // deliberate (politeness, NFR-1). Users retry from the error view.
      retry: (retryCount, error) => null,
      child: const ShowWatchApp(),
    ),
  );

  // Opened by tapping an alert while the app was closed: open the booking.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => notifications.handleLaunchDetails(),
  );
}

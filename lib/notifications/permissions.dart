import 'dart:io';

import 'package:flutter/services.dart';

import 'notification_service.dart';

/// Device permissions the alerts need, behind an interface for tests.
abstract interface class PermissionsGateway {
  /// Background alerts only work on Android in v1 (spec §4).
  bool get backgroundAlertsSupported;

  Future<bool> notificationsGranted();
  Future<bool> requestNotifications();

  /// True when the app is exempt from battery optimisation (FR-3).
  Future<bool> batteryUnrestricted();

  /// Opens the system prompt. The result arrives later; re-check
  /// [batteryUnrestricted] when the user comes back.
  Future<void> requestBatteryUnrestricted();
}

class DevicePermissions implements PermissionsGateway {
  const DevicePermissions(this._notifications);

  final NotificationService _notifications;

  /// Implemented in android/app/src/main/kotlin/.../MainActivity.kt.
  static const _battery = MethodChannel('showwatch/battery');

  @override
  bool get backgroundAlertsSupported => Platform.isAndroid;

  @override
  Future<bool> notificationsGranted() => _notifications.notificationsEnabled();

  @override
  Future<bool> requestNotifications() => _notifications.requestPermission();

  @override
  Future<bool> batteryUnrestricted() async {
    if (!Platform.isAndroid) return true;
    return await _battery.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  @override
  Future<void> requestBatteryUnrestricted() async {
    if (!Platform.isAndroid) return;
    await _battery.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// User settings (FR-20). Stored in SharedPreferences so the background
/// isolate can read them too. Pure Dart apart from the prefs instance.
class AppSettings {
  const AppSettings({
    this.defaultInterval = const Duration(minutes: 30),
    this.wifiOnly = false,
    this.alarmStyle = false,
    this.quietHours = false,
    this.quietStartMinute = 23 * 60,
    this.quietEndMinute = 7 * 60,
    this.dailyDataLimitMb = 0,
  });

  final Duration defaultInterval;

  /// Background checks only on unmetered networks.
  final bool wifiOnly;

  /// Play alerts on the alarm stream (FR-16).
  final bool alarmStyle;

  /// During quiet hours alerts still arrive, but silently.
  final bool quietHours;
  final int quietStartMinute;
  final int quietEndMinute;

  /// Estimated MB per day for background checks; 0 = no limit.
  final int dailyDataLimitMb;

  static const _p = 'settings.';
  static const keyInterval = '${_p}defaultIntervalMinutes';
  static const keyWifiOnly = '${_p}wifiOnly';
  static const keyAlarmStyle = 'alerts.alarmStyle';
  static const keyQuiet = '${_p}quietHours';
  static const keyQuietStart = '${_p}quietStart';
  static const keyQuietEnd = '${_p}quietEnd';
  static const keyDataLimit = '${_p}dailyDataLimitMb';

  factory AppSettings.read(SharedPreferences p) => AppSettings(
    defaultInterval: Duration(minutes: p.getInt(keyInterval) ?? 30),
    wifiOnly: p.getBool(keyWifiOnly) ?? false,
    alarmStyle: p.getBool(keyAlarmStyle) ?? false,
    quietHours: p.getBool(keyQuiet) ?? false,
    quietStartMinute: p.getInt(keyQuietStart) ?? 23 * 60,
    quietEndMinute: p.getInt(keyQuietEnd) ?? 7 * 60,
    dailyDataLimitMb: p.getInt(keyDataLimit) ?? 0,
  );

  Future<void> write(SharedPreferences p) async {
    await p.setInt(keyInterval, defaultInterval.inMinutes);
    await p.setBool(keyWifiOnly, wifiOnly);
    await p.setBool(keyAlarmStyle, alarmStyle);
    await p.setBool(keyQuiet, quietHours);
    await p.setInt(keyQuietStart, quietStartMinute);
    await p.setInt(keyQuietEnd, quietEndMinute);
    await p.setInt(keyDataLimit, dailyDataLimitMb);
  }

  AppSettings copyWith({
    Duration? defaultInterval,
    bool? wifiOnly,
    bool? alarmStyle,
    bool? quietHours,
    int? quietStartMinute,
    int? quietEndMinute,
    int? dailyDataLimitMb,
  }) => AppSettings(
    defaultInterval: defaultInterval ?? this.defaultInterval,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    alarmStyle: alarmStyle ?? this.alarmStyle,
    quietHours: quietHours ?? this.quietHours,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    dailyDataLimitMb: dailyDataLimitMb ?? this.dailyDataLimitMb,
  );

  /// True when [t] falls in quiet hours (the window may wrap midnight).
  bool inQuietHours(DateTime t) {
    if (!quietHours || quietStartMinute == quietEndMinute) return false;
    final m = t.hour * 60 + t.minute;
    return quietStartMinute < quietEndMinute
        ? m >= quietStartMinute && m < quietEndMinute
        : m >= quietStartMinute || m < quietEndMinute;
  }
}

/// Estimated data used by background checks today (NFR-2: one showtimes
/// page is ~87 KB gzipped).
class DataUsage {
  const DataUsage(this.day, this.pages);

  static const bytesPerPage = 87 * 1024;
  static const _kDay = 'usage.day';
  static const _kPages = 'usage.pages';

  final String day;
  final int pages;

  double get megabytes => pages * bytesPerPage / (1024 * 1024);

  static String dayOf(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static DataUsage read(SharedPreferences p, DateTime now) {
    final today = dayOf(now);
    return p.getString(_kDay) == today
        ? DataUsage(today, p.getInt(_kPages) ?? 0)
        : DataUsage(today, 0);
  }

  static Future<void> add(SharedPreferences p, DateTime now, int pages) async {
    if (pages <= 0) return;
    final current = read(p, now);
    await p.setString(_kDay, current.day);
    await p.setInt(_kPages, current.pages + pages);
  }

  bool overLimit(AppSettings s) =>
      s.dailyDataLimitMb > 0 && megabytes >= s.dailyDataLimitMb;
}

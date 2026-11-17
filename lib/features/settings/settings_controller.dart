import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs/prefs.dart';
import '../../core/settings.dart';
import '../alerts/alerts_providers.dart';

/// Current settings; changes are persisted, pushed to the notification
/// service and re-applied to the background schedule.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.read(ref.watch(sharedPrefsProvider));

  Future<void> update(AppSettings next) async {
    final wifiChanged = next.wifiOnly != state.wifiOnly;
    await next.write(ref.read(sharedPrefsProvider));
    state = next;
    ref.read(notificationSettingsSinkProvider)(next);
    if (wifiChanged) await ref.read(alertsControllerProvider).refresh();
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Today's estimated background data use (written by the worker isolate).
final dataUsageProvider = FutureProvider<DataUsage>((ref) async {
  final prefs = ref.watch(sharedPrefsProvider);
  await prefs.reload();
  return DataUsage.read(prefs, DateTime.now());
});

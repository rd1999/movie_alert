import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_alert/core/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtime_core/showtime_core.dart';

import 'support/test_app.dart';

void main() {
  group('AppSettings', () {
    test('quiet hours, including windows that wrap midnight', () {
      const night = AppSettings(
        quietHours: true,
        quietStartMinute: 23 * 60,
        quietEndMinute: 7 * 60,
      );
      expect(night.inQuietHours(DateTime(2026, 12, 18, 23, 30)), isTrue);
      expect(night.inQuietHours(DateTime(2026, 12, 18, 3)), isTrue);
      expect(night.inQuietHours(DateTime(2026, 12, 18, 7)), isFalse);
      expect(night.inQuietHours(DateTime(2026, 12, 18, 12)), isFalse);

      const lunch = AppSettings(
        quietHours: true,
        quietStartMinute: 13 * 60,
        quietEndMinute: 14 * 60,
      );
      expect(lunch.inQuietHours(DateTime(2026, 12, 18, 13, 15)), isTrue);
      expect(lunch.inQuietHours(DateTime(2026, 12, 18, 14, 1)), isFalse);

      expect(
        const AppSettings().inQuietHours(DateTime(2026, 12, 18, 3)),
        isFalse,
        reason: 'off by default',
      );
    });

    test('persist and read back', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      const s = AppSettings(
        defaultInterval: Duration(hours: 1),
        wifiOnly: true,
        alarmStyle: true,
        quietHours: true,
        quietStartMinute: 60,
        quietEndMinute: 120,
        dailyDataLimitMb: 25,
      );
      await s.write(p);
      final back = AppSettings.read(p);
      expect(back.defaultInterval, const Duration(hours: 1));
      expect(back.wifiOnly, isTrue);
      expect(back.alarmStyle, isTrue);
      expect(back.quietStartMinute, 60);
      expect(back.dailyDataLimitMb, 25);
    });
  });

  group('DataUsage', () {
    test(
      'accumulates per day, resets the next day, enforces the limit',
      () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final day1 = DateTime(2026, 12, 18, 10);
        await DataUsage.add(p, day1, 100);
        await DataUsage.add(p, day1.add(const Duration(hours: 2)), 200);
        final u = DataUsage.read(p, day1);
        expect(u.pages, 300);
        expect(u.megabytes, closeTo(25.5, 0.1));
        expect(u.overLimit(const AppSettings(dailyDataLimitMb: 25)), isTrue);
        expect(u.overLimit(const AppSettings(dailyDataLimitMb: 50)), isFalse);
        expect(u.overLimit(const AppSettings()), isFalse, reason: 'no limit');

        expect(DataUsage.read(p, DateTime(2026, 12, 19, 0, 1)).pages, 0);
      },
    );
  });

  group('settings screen', () {
    testWidgets('Wi-Fi only reaches the background schedule', (tester) async {
      final app = TestApp();
      await app.pump(tester, prefs: {'city.key': 'kolkata'});
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Background checks on Wi-Fi only'));
      await tester.pumpAndSettle();
      expect(app.scheduler.lastWifiOnly, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppSettings.keyWifiOnly), isTrue);
    });

    testWidgets('default interval is used for new alerts', (tester) async {
      final app = TestApp();
      await app.pump(
        tester,
        prefs: {'city.key': 'kolkata', AppSettings.keyInterval: 60},
      );
      await tester.tap(find.text('Test Doomsday'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alert me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any new cinema'));
      await tester.pumpAndSettle();
      final button = find.text('Create alert');
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(app.store.byId.values.single.interval, const Duration(hours: 1));
      expect(app.store.byId.values.single.condition, isA<NewCinemaAnywhere>());
    });
  });
}

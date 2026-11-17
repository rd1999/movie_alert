import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/prefs/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      // No automatic retries: every request to the listings site is
      // deliberate (politeness, NFR-1). Users retry from the error view.
      retry: (retryCount, error) => null,
      child: const ShowWatchApp(),
    ),
  );
}

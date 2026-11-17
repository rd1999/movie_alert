import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/foreground_checker.dart';
import 'router.dart';
import 'theme.dart';

class ShowWatchApp extends ConsumerWidget {
  const ShowWatchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ShowWatch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          ForegroundChecker(child: child ?? const SizedBox.shrink()),
    );
  }
}

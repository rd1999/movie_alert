import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class ShowWatchApp extends StatelessWidget {
  const ShowWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ShowWatch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}

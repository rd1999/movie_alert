import 'package:flutter/material.dart';

/// Neutral branding on purpose: never use District/BookMyShow/cinema-chain
/// colours or marks (spec §5).
abstract final class AppTheme {
  static const _seed = Color(0xFF3F51B5);

  static final light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
    useMaterial3: true,
  );

  static final dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}

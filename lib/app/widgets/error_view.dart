import 'dart:io';

import 'package:flutter/material.dart';
import 'package:showtime_core/io.dart';
import 'package:showtime_core/showtime_core.dart';

/// Error state that never pretends there is "no data" (NFR-4).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, detail) = switch (error) {
      SourceFormatChanged e => (
        Icons.build_circle_outlined,
        'Data source changed — update needed',
        'The listings page no longer looks the way this app expects, so it '
            "can't tell which shows exist.\n\n${e.message}",
      ),
      HttpStatusException(statusCode: 429) => (
        Icons.hourglass_bottom,
        'Too many requests',
        'The listings site asked us to slow down. Try again in a few minutes.',
      ),
      HttpStatusException e => (
        Icons.cloud_off,
        "Couldn't load listings",
        'The site answered HTTP ${e.statusCode}.',
      ),
      SocketException() || HttpException() => (
        Icons.wifi_off,
        "You're offline",
        'Check your connection and try again.',
      ),
      _ => (Icons.error_outline, 'Something went wrong', '$error'),
    };
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Movie list -> showtimes grid (FR-4..FR-9). Placeholder until Phase 1.
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShowWatch')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Showtimes and alerts are coming soon.\n'
            'Data from public cinema listings.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

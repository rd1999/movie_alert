import 'package:flutter/material.dart';

import '../format.dart';

/// Shown when the network failed and we're displaying the last saved copy
/// (FR-9). Never used for a changed page format (that's an error).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.fetchedAt});

  final DateTime fetchedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Offline — showing listings saved ${Fmt.ago(fetchedAt)}. "
              'Pull to refresh when you are back online.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

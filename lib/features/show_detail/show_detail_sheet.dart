import 'package:flutter/material.dart';
import 'package:showtime_core/showtime_core.dart';

import '../../app/format.dart';
import '../../app/widgets/availability.dart';
import 'booking_launcher.dart';

/// Seat classes, prices, seats left, cancellable, "Open booking" (FR-7).
class ShowDetailSheet extends StatelessWidget {
  const ShowDetailSheet({
    super.key,
    required this.movieName,
    required this.cinema,
    required this.show,
    required this.listingDate,
    required this.bookingUrl,
  });

  final String movieName;
  final Cinema cinema;
  final Show show;
  final String listingDate;
  final Uri bookingUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextDay = !show.rawShowTime.startsWith(listingDate);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(movieName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(cinema.name, style: theme.textTheme.titleSmall),
            if (cinema.address case final a?)
              Text(a, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(
              '${Fmt.listingDate(listingDate)} · ${Fmt.time(show.showTime)}'
              '${nextDay ? ' (${Fmt.listingDate(show.rawShowTime.substring(0, 10))}, late night)' : ''}',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              [?show.screenFormat, ?show.premiumLabel, ?show.audi].join(' · '),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${show.seatsAvailable} of ${show.seatsTotal} seats left · '
              '${show.availability.label}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: show.availability.color(theme.colorScheme),
              ),
            ),
            Text(
              [
                if (cinema.isCancellable == true) 'Cancellation available',
                if (show.maxTickets case final m?) 'Max $m tickets',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (show.seatClasses.isNotEmpty) ...[
              Text('Seat classes', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final a in show.seatClasses)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.label),
                  subtitle: Text(
                    '${a.available} of ${a.total} left · ${a.availability.label}',
                    style: TextStyle(
                      color: a.availability.color(theme.colorScheme),
                    ),
                  ),
                  trailing: Text(
                    Fmt.price(a.price),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => openBooking(context, bookingUrl),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open booking'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Opens the official booking page. ShowWatch never books or takes payments.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

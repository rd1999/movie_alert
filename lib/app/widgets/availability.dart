import 'package:flutter/material.dart';
import 'package:showtime_core/showtime_core.dart';

/// Colour + text for seat availability. Colour is never the only signal
/// (NFR-7): every use also shows the label or "N left".
extension AvailabilityStyle on SeatAvailability {
  String get label => switch (this) {
    SeatAvailability.available => 'Available',
    SeatAvailability.fillingFast => 'Filling fast',
    SeatAvailability.almostFull => 'Almost full',
    SeatAvailability.soldOut => 'Sold out',
    SeatAvailability.unknown => 'Unknown',
  };

  Color color(ColorScheme scheme) => switch (this) {
    SeatAvailability.available => const Color(0xFF2E7D32),
    SeatAvailability.fillingFast => const Color(0xFFB26A00),
    SeatAvailability.almostFull => const Color(0xFFC62828),
    SeatAvailability.soldOut => scheme.outline,
    SeatAvailability.unknown => scheme.outline,
  };
}

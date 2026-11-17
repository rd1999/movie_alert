/// Thrown when a page no longer has the structure the parser expects.
/// Must surface as "Data source changed — update needed", never as
/// "no shows" (spec §6.5, NFR-4).
class SourceFormatChanged implements Exception {
  SourceFormatChanged(this.message, {this.path});

  final String message;

  /// JSON path that was missing or had an unexpected type.
  final String? path;

  @override
  String toString() => path == null
      ? 'SourceFormatChanged: $message'
      : 'SourceFormatChanged: $message (at $path)';
}

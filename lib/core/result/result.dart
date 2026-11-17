/// Minimal Result type so callers must handle failures explicitly
/// (a failure must never be shown as "no shows" — NFR-4).
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No network, timeout, HTTP error, rate limited.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {this.statusCode});
  final int? statusCode;
}

/// The data source's page structure changed: "Data source changed — update
/// needed" (spec §6.5).
final class SourceChangedFailure extends Failure {
  const SourceChangedFailure(super.message);
}

/// Exceptions thrown by the FileMaker Data API client.
library;

/// Base class for all errors surfaced by this package.
class FileMakerException implements Exception {
  /// Creates a [FileMakerException].
  const FileMakerException(this.message, {this.code});

  /// Human-readable description of what went wrong.
  final String message;

  /// FileMaker error code, when the host returned one. See
  /// https://help.claris.com/en/pro-help/content/error-codes.html
  final int? code;

  @override
  String toString() =>
      'FileMakerException(${code != null ? 'code: $code, ' : ''}$message)';
}

/// Thrown when authentication fails or a session token is rejected.
class FileMakerAuthException extends FileMakerException {
  /// Creates a [FileMakerAuthException].
  const FileMakerAuthException(super.message, {super.code});
}

/// Thrown when a find request matches no records (FileMaker error 401).
///
/// This is separated out because "no records found" is frequently an
/// expected, non-fatal outcome that callers want to handle explicitly
/// rather than as a hard error.
class FileMakerNoRecordsException extends FileMakerException {
  /// Creates a [FileMakerNoRecordsException].
  const FileMakerNoRecordsException(super.message, {super.code = 401});
}

/// Thrown when the host is unreachable or returns a non-JSON / transport error.
class FileMakerTransportException extends FileMakerException {
  /// Creates a [FileMakerTransportException].
  const FileMakerTransportException(super.message, {super.code});
}

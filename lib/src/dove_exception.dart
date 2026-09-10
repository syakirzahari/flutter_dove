/// Thrown when a request to the OST Push backend fails.
class DoveException implements Exception {
  DoveException(
    this.message, {
    this.statusCode,
    this.errors,
  });

  /// Human-readable message returned by the API (or a local description).
  final String message;

  /// HTTP status code of the failed response, when available.
  final int? statusCode;

  /// Laravel-style field validation errors, when the response was a 422.
  final Map<String, List<String>>? errors;

  @override
  String toString() {
    final code = statusCode != null ? ' ($statusCode)' : '';
    return 'DoveException$code: $message';
  }
}

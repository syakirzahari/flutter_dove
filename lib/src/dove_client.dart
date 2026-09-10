import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dove_exception.dart';

/// Thin HTTP client for the OST Push backend's `/api` surface.
///
/// Mirrors the routes exposed by `routes/api.php` in the `ost-push` Laravel
/// app: device registration/identification/logout, device removal, and
/// per-topic subscribe/unsubscribe. Every request is authenticated with the
/// per-app API key as a bearer token, matching `AuthenticateApiKey`.
class DoveClient {
  DoveClient({
    required Uri baseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _baseUrl = _withoutTrailingSlash(baseUrl),
       _http = httpClient ?? http.Client();

  final Uri _baseUrl;
  final String apiKey;
  final http.Client _http;

  static Uri _withoutTrailingSlash(Uri uri) {
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl/$path');

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  };

  /// Registers (or updates) a device for the authenticated app.
  ///
  /// `POST /api/devices` — upserts by `device_id`.
  Future<Map<String, dynamic>> registerDevice({
    required String deviceId,
    required String fcmToken,
    String? platform,
    String? appVersion,
  }) {
    return _post('api/devices', {
      'device_id': deviceId,
      'fcm_token': fcmToken,
      'platform': ?platform,
      'app_version': ?appVersion,
    });
  }

  /// Associates the device with an app-side user id.
  ///
  /// `POST /api/devices/identify`
  Future<Map<String, dynamic>> identifyDevice({
    required String deviceId,
    required String userId,
  }) {
    return _post('api/devices/identify', {
      'device_id': deviceId,
      'user_id': userId,
    });
  }

  /// Clears the user association from a device (app-side logout).
  ///
  /// `POST /api/devices/logout`
  Future<Map<String, dynamic>> logoutDevice({required String deviceId}) {
    return _post('api/devices/logout', {'device_id': deviceId});
  }

  /// Unregisters (soft-deletes) a device.
  ///
  /// `DELETE /api/devices/{deviceId}`
  Future<void> deleteDevice({required String deviceId}) {
    return _delete('api/devices/${Uri.encodeComponent(deviceId)}');
  }

  /// Subscribes a device to a topic.
  ///
  /// `POST /api/topics/{topic}/subscribe`
  Future<Map<String, dynamic>> subscribeTopic({
    required String topic,
    required String deviceId,
  }) {
    return _post('api/topics/${Uri.encodeComponent(topic)}/subscribe', {
      'device_id': deviceId,
    });
  }

  /// Unsubscribes a device from a topic.
  ///
  /// `POST /api/topics/{topic}/unsubscribe`
  Future<Map<String, dynamic>> unsubscribeTopic({
    required String topic,
    required String deviceId,
  }) {
    return _post('api/topics/${Uri.encodeComponent(topic)}/unsubscribe', {
      'device_id': deviceId,
    });
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<void> _delete(String path) async {
    final response = await _http.delete(_uri(path), headers: _headers);
    if (response.statusCode == 204) return;
    _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    Map<String, dynamic> body = const {};

    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        if (isSuccess) {
          throw DoveException(
            'Received a non-JSON response from the server.',
            statusCode: response.statusCode,
          );
        }
      }
    }

    if (isSuccess) return body;

    final rawErrors = body['errors'];
    throw DoveException(
      (body['message'] as String?) ??
          'Request failed with status ${response.statusCode}.',
      statusCode: response.statusCode,
      errors: rawErrors is Map<String, dynamic>
          ? rawErrors.map(
              (key, value) => MapEntry(
                key,
                (value as List).map((e) => e.toString()).toList(),
              ),
            )
          : null,
    );
  }

  /// Releases the underlying HTTP client's resources.
  void close() => _http.close();
}

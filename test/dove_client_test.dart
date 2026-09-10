import 'dart:convert';

import 'package:flutter_dove/flutter_dove.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DoveClient', () {
    test('registerDevice posts the expected payload and headers', () async {
      http.Request? captured;

      final client = DoveClient(
        baseUrl: Uri.parse('https://push.example.com'),
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'data': {'id': 'dev_1', 'device_id': 'device-abc'},
            }),
            201,
          );
        }),
      );

      final result = await client.registerDevice(
        deviceId: 'device-abc',
        fcmToken: 'fcm-token',
        platform: 'android',
        appVersion: '1.0.0+1',
      );

      expect(captured!.method, 'POST');
      expect(captured!.url.toString(), 'https://push.example.com/api/devices');
      expect(captured!.headers['Authorization'], 'Bearer test-key');
      expect(
        jsonDecode(captured!.body),
        {
          'device_id': 'device-abc',
          'fcm_token': 'fcm-token',
          'platform': 'android',
          'app_version': '1.0.0+1',
        },
      );
      expect(result['data']['device_id'], 'device-abc');
    });

    test('strips a trailing slash from baseUrl', () async {
      http.Request? captured;

      final client = DoveClient(
        baseUrl: Uri.parse('https://push.example.com/'),
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await client.logoutDevice(deviceId: 'device-abc');

      expect(captured!.url.toString(), 'https://push.example.com/api/devices/logout');
    });

    test('subscribeTopic URL-encodes the topic segment', () async {
      http.Request? captured;

      final client = DoveClient(
        baseUrl: Uri.parse('https://push.example.com'),
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await client.subscribeTopic(topic: 'news updates', deviceId: 'device-abc');

      expect(captured!.url.path, '/api/topics/news%20updates/subscribe');
    });

    test('deleteDevice succeeds on 204 with no body', () async {
      final client = DoveClient(
        baseUrl: Uri.parse('https://push.example.com'),
        apiKey: 'test-key',
        httpClient: MockClient((request) async => http.Response('', 204)),
      );

      await expectLater(client.deleteDevice(deviceId: 'device-abc'), completes);
    });

    test('throws DoveException with message and field errors on 422', () async {
      final client = DoveClient(
        baseUrl: Uri.parse('https://push.example.com'),
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'message': 'The fcm token field is required.',
              'errors': {
                'fcm_token': ['The fcm token field is required.'],
              },
            }),
            422,
          );
        }),
      );

      try {
        await client.registerDevice(deviceId: 'device-abc', fcmToken: '');
        fail('Expected a DoveException to be thrown.');
      } on DoveException catch (e) {
        expect(e.statusCode, 422);
        expect(e.message, 'The fcm token field is required.');
        expect(e.errors?['fcm_token'], ['The fcm token field is required.']);
      }
    });

    test('throws DoveException on 401 with the backend message', () async {
      final client = DoveClient(
        baseUrl: Uri.parse('https://push.example.com'),
        apiKey: 'bad-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'message': 'Invalid or revoked API key.'}),
            401,
          );
        }),
      );

      await expectLater(
        client.registerDevice(deviceId: 'device-abc', fcmToken: 'fcm-token'),
        throwsA(
          isA<DoveException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Invalid or revoked API key.'),
        ),
      );
    });
  });
}

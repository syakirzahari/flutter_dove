import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'dove_client.dart';
import 'dove_device_id_store.dart';

/// Entry point for connecting an app to the OST Push backend and to Firebase
/// Cloud Messaging.
///
/// Call [initialize] once (typically in `main()`, after `Firebase.initializeApp`
/// has been configured for the platform via FlutterFire). From then on the
/// current device is kept registered with the backend, and [onMessage] /
/// [onMessageOpenedApp] surface incoming notifications.
class FlutterDove {
  FlutterDove._();

  /// Singleton instance.
  static final FlutterDove instance = FlutterDove._();

  DoveClient? _client;
  final DoveDeviceIdStore _deviceIdStore = DoveDeviceIdStore();
  String? _deviceId;
  StreamSubscription<String>? _tokenRefreshSubscription;

  final StreamController<RemoteMessage> _onMessageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _onMessageOpenedAppController =
      StreamController<RemoteMessage>.broadcast();

  /// Notifications received while the app is in the foreground.
  Stream<RemoteMessage> get onMessage => _onMessageController.stream;

  /// Fired when the user taps a notification and the app opens from the
  /// background as a result.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      _onMessageOpenedAppController.stream;

  /// The device identifier registered with the backend, once [initialize]
  /// has completed.
  String? get deviceId => _deviceId;

  /// The current FCM registration token.
  Future<String?> get token => FirebaseMessaging.instance.getToken();

  /// Sets up Firebase Messaging and registers this device with the OST Push
  /// backend at [baseUrl] using [apiKey].
  ///
  /// [baseUrl] is the root URL of the `ost-push` deployment (e.g.
  /// `https://push.example.com`) — the `/api/...` paths are appended
  /// automatically. [apiKey] is the raw per-app key issued via the backend's
  /// API key management screen (sent as `Authorization: Bearer <apiKey>`).
  ///
  /// Pass [firebaseOptions] to initialize Firebase from those values
  /// directly — skipping `flutterfire configure` and the native
  /// `google-services.json` / `GoogleService-Info.plist` files. Omit it if
  /// `Firebase.initializeApp()` has already been (or will be) called
  /// elsewhere, e.g. via those generated files.
  ///
  /// Set [requestPermission] to `false` if your app requests notification
  /// permission itself elsewhere.
  Future<void> initialize({
    required String baseUrl,
    required String apiKey,
    FirebaseOptions? firebaseOptions,
    bool requestPermission = true,
    http.Client? httpClient,
  }) async {
    await ensureFirebaseInitialized(options: firebaseOptions);

    _client = DoveClient(
      baseUrl: Uri.parse(baseUrl),
      apiKey: apiKey,
      httpClient: httpClient,
    );

    _deviceId = await _deviceIdStore.getOrCreate();

    final messaging = FirebaseMessaging.instance;

    if (requestPermission) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }

    await _registerCurrentDevice();

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) {
      unawaited(_registerCurrentDevice(fcmToken: newToken));
    });

    FirebaseMessaging.onMessage.listen(_onMessageController.add);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedAppController.add);
  }

  /// Initializes the default Firebase app if it hasn't been already.
  ///
  /// Call this at the top of a top-level `@pragma('vm:entry-point')`
  /// background message handler passed to
  /// `FirebaseMessaging.onBackgroundMessage` — that handler runs in its own
  /// isolate, which has not run [initialize]. Pass the same [options] used
  /// in [initialize] if you initialized Firebase from inline
  /// [FirebaseOptions] rather than native config files, since the
  /// background isolate has no other way to discover them.
  static Future<void> ensureFirebaseInitialized({FirebaseOptions? options}) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
  }

  Future<void> _registerCurrentDevice({String? fcmToken}) async {
    final client = _client;
    final deviceId = _deviceId;
    if (client == null || deviceId == null) return;

    final resolvedToken = fcmToken ?? await FirebaseMessaging.instance.getToken();
    if (resolvedToken == null) return;

    await client.registerDevice(
      deviceId: deviceId,
      fcmToken: resolvedToken,
      platform: _platformName,
      appVersion: await _appVersion(),
    );
  }

  String? get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  /// Associates the current device with [userId] on the backend, e.g. after
  /// the app's own sign-in completes.
  Future<void> identify(String userId) async {
    final client = _requireClient();
    await client.identifyDevice(deviceId: _requireDeviceId(), userId: userId);
  }

  /// Clears the user association for the current device, e.g. on app
  /// sign-out — leaves the device (and its FCM token) registered.
  Future<void> logout() async {
    final client = _requireClient();
    await client.logoutDevice(deviceId: _requireDeviceId());
  }

  /// Subscribes the current device to [topic].
  Future<void> subscribeTopic(String topic) async {
    final client = _requireClient();
    await client.subscribeTopic(topic: topic, deviceId: _requireDeviceId());
  }

  /// Unsubscribes the current device from [topic].
  Future<void> unsubscribeTopic(String topic) async {
    final client = _requireClient();
    await client.unsubscribeTopic(topic: topic, deviceId: _requireDeviceId());
  }

  /// Unregisters the current device from the backend and forgets the local
  /// device id, e.g. when the user opts out of push notifications entirely.
  Future<void> unregister() async {
    final client = _requireClient();
    await client.deleteDevice(deviceId: _requireDeviceId());
    await _deviceIdStore.clear();
    _deviceId = null;
  }

  DoveClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('FlutterDove.initialize() must be called first.');
    }
    return client;
  }

  String _requireDeviceId() {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('FlutterDove.initialize() must be called first.');
    }
    return deviceId;
  }

  /// Cancels internal subscriptions and closes the event streams. Optional —
  /// intended for tests or apps that fully tear down push support at
  /// runtime.
  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _client?.close();
    _client = null;
    _deviceId = null;
  }
}

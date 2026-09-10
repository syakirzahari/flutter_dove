# flutter_dove

Connects a Flutter app to an [`ost-push`](https://github.com/) backend: registers
the device and its Firebase Cloud Messaging token, keeps the registration fresh
across token refreshes, and surfaces incoming push notifications.

It is a thin Dart client for the backend's `/api` surface
(`routes/api.php` / `App\Http\Controllers\Api\*` in `ost-push`) plus a
`FirebaseMessaging` wrapper — it does not replace `firebase_messaging`, it
drives it.

## Features

- Registers the device (`POST /api/devices`) with a stable, persisted
  `device_id`, the current FCM token, platform, and app version.
- Re-registers automatically on FCM token refresh.
- Associates/clears an app-side user id on the device
  (`POST /api/devices/identify`, `POST /api/devices/logout`).
- Subscribes/unsubscribes the device to topics
  (`POST /api/topics/{topic}/subscribe|unsubscribe`).
- Unregisters the device (`DELETE /api/devices/{deviceId}`).
- Exposes `onMessage` / `onMessageOpenedApp` streams of incoming
  `RemoteMessage`s.

## Getting started

Steps to wire `flutter_dove` into an existing Flutter app.

### 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  flutter_dove:
    git:
      url: https://github.com/your-org/flutter_dove.git
      # or, once published: flutter_dove: ^0.0.1
```

```bash
flutter pub get
```

### 2. Configure Firebase

This package doesn't configure Firebase itself — it drives whatever
`firebase_core`/`firebase_messaging` setup your app already has. Pick one:

**Option A — FlutterFire CLI (generates native config files):**

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This generates `lib/firebase_options.dart` and drops the platform config
files (`android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist`) into place. Then call
`FlutterDove.instance.initialize(baseUrl: ..., apiKey: ...)` without
`firebaseOptions` — it calls `Firebase.initializeApp()` for you and picks
those files up automatically.

**Option B — inline `FirebaseOptions` (no CLI, no config files):**

Register an Android/iOS app under the *same* Firebase project the backend
already uses (Firebase console → Project settings → Your apps → Add app —
no need to download anything from that screen), then copy the small set of
public client values it shows you (`apiKey`, `appId`, `messagingSenderId`,
`projectId`) straight into code:

```dart
await FlutterDove.instance.initialize(
  baseUrl: const String.fromEnvironment('OST_PUSH_BASE_URL'),
  apiKey: const String.fromEnvironment('OST_PUSH_API_KEY'),
  firebaseOptions: const FirebaseOptions(
    apiKey: 'AIza...',
    appId: '1:1234567890:android:abcdef',
    messagingSenderId: '1234567890',
    projectId: 'your-firebase-project-id',
  ),
);
```

No `flutterfire configure`, no `google-services.json` /
`GoogleService-Info.plist`, no Google Services Gradle plugin. These values
aren't secret (they already ship inside every Firebase app's binary) — they
just tell the device which Firebase project to register with. iOS still
needs its APNs key uploaded to that same Firebase project (see step 4) —
that requirement is Apple's, not Firebase's config-file mechanism.

### 3. Android setup

- Confirm `android/app/build.gradle(.kts)` has `minSdk 21` or higher (FCM
  requirement).
- Option A only: the Google Services Gradle plugin must be applied (added
  automatically by `flutterfire configure`). Option B doesn't need it.
- No extra manifest entries are required for `flutter_dove` itself —
  `firebase_messaging` registers its own service. If you want a custom
  notification icon/color for data-only or high-priority notifications, set
  the standard meta-data in `android/app/src/main/AndroidManifest.xml`:

  ```xml
  <meta-data
      android:name="com.google.firebase.messaging.default_notification_icon"
      android:resource="@drawable/ic_notification" />
  ```

### 4. iOS setup

- In Xcode (`ios/Runner.xcworkspace`), add the **Push Notifications** and
  **Background Modes → Remote notifications** capabilities to the `Runner`
  target.
- Upload an APNs key/certificate for the app in the Firebase console
  (Project settings → Cloud Messaging → Apple app configuration).
- Set the iOS deployment target to 13.0+ in `ios/Podfile` and
  `ios/Runner.xcodeproj`.

### 5. Get a backend API key

In the `ost-push` admin, create/select a tenant app and issue an API key for
it (sent as `Authorization: Bearer <key>` — see `AuthenticateApiKey`). Keep
this key out of source control — pass it in at build time instead:

```bash
flutter run --dart-define=OST_PUSH_API_KEY=xxxxx --dart-define=OST_PUSH_BASE_URL=https://ostmerpati.tryzone.my
```

### 6. Initialize in `main()`

Wire up Firebase, the background handler, and `FlutterDove.initialize` before
`runApp` — see [Usage](#usage) below for the full snippet.

## Usage

Using Option B (inline `FirebaseOptions`) — the same options must be
available to the background isolate too, so keep them in a shared constant:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dove/flutter_dove.dart';

const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIza...',
  appId: '1:1234567890:android:abcdef',
  messagingSenderId: '1234567890',
  projectId: 'your-firebase-project-id',
);

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Background messages run in a separate isolate, so Firebase needs to be
  // (re-)initialized here before doing anything with it.
  await FlutterDove.ensureFirebaseInitialized(options: _firebaseOptions);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  await FlutterDove.instance.initialize(
    baseUrl: const String.fromEnvironment('OST_PUSH_BASE_URL'),
    apiKey: const String.fromEnvironment('OST_PUSH_API_KEY'),
    firebaseOptions: _firebaseOptions,
  );

  runApp(const MyApp());
}
```

Using Option A (`flutterfire configure`), drop `firebaseOptions` from both
calls above — `initialize()` and `ensureFirebaseInitialized()` fall back to
`Firebase.initializeApp()`, which reads the generated config files.

Listening for notifications:

```dart
FlutterDove.instance.onMessage.listen((message) {
  // App is in the foreground.
  print(message.notification?.title);
  print(message.data);
});

FlutterDove.instance.onMessageOpenedApp.listen((message) {
  // User tapped a notification and the app opened from the background.
});
```

Identifying/clearing the signed-in user, and topics:

```dart
await FlutterDove.instance.identify(currentUser.id);
await FlutterDove.instance.subscribeTopic('announcements');
await FlutterDove.instance.unsubscribeTopic('announcements');
await FlutterDove.instance.logout(); // keeps the device registered
await FlutterDove.instance.unregister(); // drops the device entirely
```

`identify`/`logout`/`subscribeTopic`/`unsubscribeTopic`/`unregister` throw a
[`DoveException`] (with `statusCode`, `message`, and, for 422 responses, a
per-field `errors` map) on failure — the same shape the backend's
`FormRequest` validation and `AuthenticateApiKey` middleware return.

See `example/lib/main.dart` for a complete app.

## Additional information

- The device id is a UUID generated on first launch and persisted with
  `shared_preferences` — it identifies the app install, not the physical
  device, matching what the backend's upsert-by-`device_id` expects.
- Notification permission (including Android 13+'s runtime permission) is
  requested automatically during `initialize()`; pass
  `requestPermission: false` to handle that elsewhere.

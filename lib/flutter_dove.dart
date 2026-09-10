// Connects a Flutter app to an OST Push (`ost-push`) backend: registers the
// device and its FCM token, keeps the registration fresh, and surfaces
// incoming Firebase Cloud Messaging notifications.

export 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
export 'package:firebase_messaging/firebase_messaging.dart'
    show
        FirebaseMessaging,
        RemoteMessage,
        RemoteNotification,
        NotificationSettings,
        AuthorizationStatus;

export 'src/dove_client.dart';
export 'src/dove_exception.dart';
export 'src/flutter_dove.dart';

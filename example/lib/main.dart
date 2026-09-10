import 'package:flutter/material.dart';
import 'package:flutter_dove/flutter_dove.dart';

// Option A (flutterfire configure) instead: delete _firebaseOptions below,
// `import 'firebase_options.dart';`, and pass
// `firebaseOptions: DefaultFirebaseOptions.currentPlatform` — or omit
// `firebaseOptions` entirely, since it also falls back to reading the
// generated native config files.
//
// Option B (this example): register an Android/iOS app under the same
// Firebase project the backend already uses, and copy its public client
// values here directly — no CLI, no google-services.json/GoogleService-Info.plist.
const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIza...',
  appId: '1:1234567890:android:abcdef',
  messagingSenderId: '1234567890',
  projectId: 'your-firebase-project-id',
);

/// Must be a top-level (or static) function, annotated with
/// `@pragma('vm:entry-point')`, so the background isolate can find it.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Background messages run in their own isolate, which hasn't run
  // initialize() — re-supply the same Firebase options here.
  await FlutterDove.ensureFirebaseInitialized(options: _firebaseOptions);
  // Handle background/data-only messages here (e.g. update local storage).
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  await FlutterDove.instance.initialize(
    baseUrl: const String.fromEnvironment('OST_PUSH_BASE_URL', defaultValue: 'https://ostmerpati.tryzone.my'),
    apiKey: const String.fromEnvironment('OST_PUSH_API_KEY'),
    firebaseOptions: _firebaseOptions,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _lastMessage;

  @override
  void initState() {
    super.initState();

    FlutterDove.instance.onMessage.listen((message) {
      setState(() {
        _lastMessage = message.notification?.title ?? message.data.toString();
      });
    });

    FlutterDove.instance.onMessageOpenedApp.listen((message) {
      // Navigate based on message.data here.
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_dove example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Device id: ${FlutterDove.instance.deviceId}'),
              const SizedBox(height: 8),
              Text('Last message: ${_lastMessage ?? '-'}'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => FlutterDove.instance.identify('user-123'),
                child: const Text('Identify as user-123'),
              ),
              ElevatedButton(
                onPressed: () => FlutterDove.instance.subscribeTopic('announcements'),
                child: const Text('Subscribe to "announcements"'),
              ),
              ElevatedButton(
                onPressed: () => FlutterDove.instance.logout(),
                child: const Text('Logout (keep device registered)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

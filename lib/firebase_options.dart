
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web is not configured. Run flutterfire configure.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'This platform is not supported.',
        );
    }
  }

  // ⚠️ TEMP PLACEHOLDER VALUES
  // These MUST be replaced by running: flutterfire configure
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'TEMP',
    appId: 'TEMP',
    messagingSenderId: 'TEMP',
    projectId: 'TEMP',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TEMP',
    appId: 'TEMP',
    messagingSenderId: 'TEMP',
    projectId: 'TEMP',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'TEMP',
    appId: 'TEMP',
    messagingSenderId: 'TEMP',
    projectId: 'TEMP',
  );
}

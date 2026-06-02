import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError('This platform is not supported.');
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAdZGHmz9cXjJ4hSQT0Pz1YMHusELtwAOc',
    authDomain: 'cricknova-5f94f.firebaseapp.com',
    projectId: 'cricknova-5f94f',
    storageBucket: 'cricknova-5f94f.firebasestorage.app',
    messagingSenderId: '974755575850',
    appId: '1:974755575850:web:79ad7eda415c43a8492b53',
  );
}

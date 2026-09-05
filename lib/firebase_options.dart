import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyBaw6Ey6FTAmcnhAq1JusVQ5WpDELu5JgA',
    appId: '1:476362648228:web:d57a0e4f1687fa1fe7d431',
    messagingSenderId: '476362648228',
    projectId: 'travel-planner-62306',
    authDomain: 'travel-planner-62306.firebaseapp.com',
    storageBucket: 'travel-planner-62306.firebasestorage.app',
    measurementId: 'G-7GFY6E6CXP',
  );

  static const vapidKey =
      'BHOKRo7ljfGKCmggOcjzSBgfcDQPqqxMN2FmxC7ujyXxV-D2Gm3qTDmDnj2MLAday1VfzfU-OEfQc8a-8BSzPPc';

  static bool get isConfigured => apiKey != 'REPLACE_WITH_FIREBASE_API_KEY';

  static String get apiKey => web.apiKey;
}

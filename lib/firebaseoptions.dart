import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyAWRsXToYWCu9-jmMhBBv7YcwB-ouJWxTU',
      authDomain: 'adminlav.firebaseapp.com',
      projectId: 'adminlav',
      storageBucket: 'adminlav.appspot.com', // CORREGIDO
      messagingSenderId: '886479922904',
      appId: '1:886479922904:web:eb7e210f1653674b4459ad',
    );
  }
}

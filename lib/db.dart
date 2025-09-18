import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Db {
  static String get uid => FirebaseAuth.instance.currentUser!.uid;

  static CollectionReference<Map<String, dynamic>> col(String name) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection(name);

  static DocumentReference<Map<String, dynamic>> cfg(String id) =>
      col('config').doc(id);
}

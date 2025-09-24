import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebaseoptions.dart';        // tu archivo con DefaultFirebaseOptions
import 'login_screen.dart';           // tu LoginScreen
import 'homescreen.dart';             // tu HomeScreen (ahora recibe role y tenantId)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AdminLav',
      home: const AuthGate(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();

        // Busca admins/{uid} para rol/tenant/active
        final adminRef = FirebaseFirestore.instance.collection('admins').doc(user.uid);
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: adminRef.get(),
          builder: (context, adminSnap) {
            if (adminSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // Si no existe o inactivo -> fuera
            if (!adminSnap.hasData || !adminSnap.data!.exists) {
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            final data = adminSnap.data!.data()!;
            final active = (data['active'] as bool?) ?? false;
            if (!active) {
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            final role = (data['role'] as String?) ?? 'operator'; // 'admin' | 'operator'
            final tenantId = (data['tenant'] as String?) ?? user.uid; // dueño: su propio uid

            // Pasa el contexto al Home
            return HomeScreen(role: role, tenantId: tenantId);
          },
        );
      },
    );
  }
}





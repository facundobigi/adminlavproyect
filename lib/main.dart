import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebaseoptions.dart';        // tu archivo con DefaultFirebaseOptions
import 'login_screen.dart';           // tu LoginScreen
import 'homescreen.dart';             // tu HomeScreen (ahora recibe role y tenantId)

// Arranca la app de inmediato y resuelve Firebase por dentro.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AdminLav',
      theme: ThemeData(useMaterial3: true),
      home: FutureBuilder<FirebaseApp>(
        // Evita que la app quede en blanco si Firebase tarda o falla.
        future: Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 20)),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done && snap.hasData) {
            return const AuthGate();
          }
          if (snap.hasError) {
            // Muestra un fallback simple con opción de reintento manual.
            return const _InitErrorScreen();
          }
          return const _SplashScreen();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          height: 36,
          width: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  const _InitErrorScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No se pudo inicializar Firebase',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                // Reintento: reconstruye el árbol volviendo al Bootstrap.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const _BootstrapApp()),
                  (route) => false,
                );
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
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
        // En web a veces tarda en inicializar; mostramos Login para evitar cuelgues.
        if (snap.connectionState == ConnectionState.waiting) {
          return const LoginScreen();
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();

        // Busca admins/{uid} para rol/tenant/active
        final adminRef = FirebaseFirestore.instance.collection('admins').doc(user.uid);
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: adminRef.get(),
          builder: (context, adminSnap) {
            if (adminSnap.connectionState == ConnectionState.waiting) {
              return const LoginScreen();
            }
            if (adminSnap.hasError) {
              return const LoginScreen();
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





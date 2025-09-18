// login_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Firestore: crear doc en admins/{uid} con { active: true } para habilitar acceso.
class _LoginScreenState extends State<LoginScreen> {
  // Estilo
  static const Color kPrimary = Color.fromARGB(255, 24, 56, 121);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 640;
  static const double _radius = 16;

  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _remember = true; // Recordarme

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signin() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance
            .setPersistence(_remember ? Persistence.LOCAL : Persistence.SESSION);
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );

      // Validación contra admins/{uid}
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snap = await FirebaseFirestore.instance.doc('admins/$uid').get();
      final ok = snap.exists && (snap.data()?['active'] == true);
      if (!ok) {
        await FirebaseAuth.instance.signOut();
        _show('Acceso no autorizado. Contactá al administrador.');
        return;
      }
      // Navegación: manejala con tu listener de auth.
    } on FirebaseAuthException catch (e) {
      _show(e.message ?? 'Error al iniciar sesión');
    } catch (_) {
      _show('Error inesperado');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: kPrimary),
        titleTextStyle: const TextStyle(
          color: kPrimary, fontSize: 20, fontWeight: FontWeight.w600,
        ),
        title: const Text('Ingresar'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _panelMaxW),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Image.asset(
                      'assets/admin.lav1.png',
                      height: 72,
                      fit: BoxFit.contain,
                      semanticLabel: 'admin.lav',
                    ),
                  ),
                ),

                // Barra
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Ingreso',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Card formulario
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_radius),
                    boxShadow: const [
                      BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          onFieldSubmitted: (_) => _signin(),
                          validator: (v) => (v != null && v.contains('@')) ? null : 'Email inválido',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pass,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                              tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                            ),
                          ),
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _signin(),
                          validator: (v) => (v != null && v.length >= 6) ? null : 'Mínimo 6 caracteres',
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Checkbox(
                              value: _remember,
                              onChanged: _busy ? null : (v) => setState(() => _remember = v ?? true),
                            ),
                            const Text('Recordarme'),
                          ],
                        ),
                        const SizedBox(height: 8),

                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            onPressed: _busy ? null : _signin,
                            child: _busy
                                ? const SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Entrar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}





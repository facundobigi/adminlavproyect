// registrogasto.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegistroGastoScreen extends StatefulWidget {
  const RegistroGastoScreen({super.key});

  @override
  State<RegistroGastoScreen> createState() => _RegistroGastoScreenState();
}

class _RegistroGastoScreenState extends State<RegistroGastoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _montoController = TextEditingController();
  bool _isLoading = false;

  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  // Paleta y tokens coherentes
  static const Color kPrimary = Color.fromARGB(255, 20, 52, 117);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 720; // un poco más ancho para desktop
  static const double _radius = 16;

  Future<void> guardarGasto() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('gastos')
          .add({
        'descripcion': _descripcionController.text.trim(),
        'monto': double.parse(_montoController.text.trim()),
        'fecha': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: kPrimary),
          titleTextStyle: const TextStyle(
            color: kPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          title: const Text('Registrar gasto'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _panelMaxW),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Barra azul
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.money_off, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Registrar gasto',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          )
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: LayoutBuilder(
                          builder: (_, c) {
                            final wide = c.maxWidth >= 560;

                            final descField = TextFormField(
                              controller: _descripcionController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Descripción',
                                hintText: 'Ej: Compra de shampoo',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'Ingresá una descripción'
                                      : null,
                            );

                            final montoField = TextFormField(
                              controller: _montoController,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => guardarGasto(),
                              decoration: const InputDecoration(
                                labelText: 'Monto',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                // permite números con hasta 2 decimales
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (value) {
                                final monto = double.tryParse(value ?? '');
                                if (monto == null || monto <= 0) {
                                  return 'Ingresá un monto válido';
                                }
                                return null;
                              },
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Ingresá los datos del gasto',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Responsive: en wide, dos columnas; en narrow, apilado
                                if (wide)
                                  Row(
                                    children: [
                                      Expanded(child: descField),
                                      const SizedBox(width: 12),
                                      SizedBox(width: 220, child: montoField),
                                    ],
                                  )
                                else ...[
                                  descField,
                                  const SizedBox(height: 12),
                                  montoField,
                                ],

                                const SizedBox(height: 24),

                                // Botón guardar (full en móvil, fijo en desktop)
                                Align(
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: wide ? 220 : double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kPrimary,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(48),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: _isLoading ? null : guardarGasto,
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Guardar'),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}





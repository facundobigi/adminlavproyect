// servicios_screen.dart
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ServiciosScreen extends StatefulWidget {
  const ServiciosScreen({super.key});
  @override
  State<ServiciosScreen> createState() => _ServiciosScreenState();
}

class _ServiciosScreenState extends State<ServiciosScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 18, 48, 107);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 720;
  static const double _radius = 16;

  // -------- Helpers visualización --------
  double _parseMoney(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^0-9,\. ,]'), '');
    final normalized = cleaned.replaceAll('.', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  final NumberFormat _money =
      NumberFormat.currency(locale: 'es_AR', symbol: r'$');
  String _fmtMoney(num v) => _money.format(v);

  String _fmtDurMin(int mins) {
    final h = mins ~/ 60, m = mins % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  // -------- Helpers nombre Title Case --------
  String _cleanSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  String _cap(String w) =>
      w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
  String _titleCase(String s) =>
      _cleanSpaces(s).split(' ').map((p) => p.split('-').map(_cap).join('-')).join(' ');

  // InputFormatter para nombre con caracteres ES
  static final _nombreAllow =
      FilteringTextInputFormatter.allow(RegExp(r"[ A-Za-zÁÉÍÓÚÜÑáéíóúüñ'´\-]"));

  // -------- Editor (con showGeneralDialog estable en web) --------
  Future<void> _showEdit({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
  final data = doc?.data() ?? {};
  final nombre = TextEditingController(text: _titleCase((data['nombre'] ?? '') as String));
  final precio = TextEditingController(
    text: (data['precio'] is num) ? (data['precio'] as num).toStringAsFixed(0) : '',
  );
  final dur = (data['duracion_min'] as num?)?.toInt() ?? 0;
  final horas = TextEditingController(text: (dur ~/ 60).toString());
  final minutos = TextEditingController(text: (dur % 60).toString());
  final form = GlobalKey<FormState>();

  Future<void> guardar() async {
    if (!form.currentState!.validate()) return;
    final h = int.tryParse(horas.text) ?? 0;
    final m = int.tryParse(minutos.text) ?? 0;
    final durMin = h * 60 + m;
    final price = _parseMoney(precio.text);
    if (durMin <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duración debe ser > 0')),
        );
      }
      return;
    }
    final payload = {
      'nombre': _titleCase(nombre.text),
      'precio': price,
      'duracion_min': durMin,
      'updated_at': FieldValue.serverTimestamp(),
      if (doc == null) 'activo': true,
    };
    final col = FirebaseFirestore.instance
        .collection('users').doc(_uid).collection('servicios');
    if (doc == null) {
      await col.add({...payload, 'created_at': FieldValue.serverTimestamp()});
    } else {
      await doc.reference.update(payload);
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop(true);
  }

  final res = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    useSafeArea: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(doc == null ? 'Nuevo servicio' : 'Editar servicio',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nombre,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej: Lavado Premium'),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [_nombreAllow, LengthLimitingTextInputFormatter(40)],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  onEditingComplete: () {
                    nombre.text = _titleCase(nombre.text);
                    FocusScope.of(context).nextFocus();
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: precio,
                  decoration: const InputDecoration(labelText: 'Precio', prefixText: '\$ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  validator: (v) => _parseMoney(v ?? '') > 0 ? null : 'Inválido',
                ),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (_, c) {
                  final narrow = c.maxWidth < 420;
                  final horasField = TextFormField(
                    controller: horas,
                    decoration: const InputDecoration(labelText: 'Horas'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) >= 0 ? null : 'Inválido',
                  );
                  final minutosField = TextFormField(
                    controller: minutos,
                    decoration: const InputDecoration(labelText: 'Minutos (0–59)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final m = int.tryParse(v ?? '') ?? -1;
                      return (m >= 0 && m < 60) ? null : '0–59';
                    },
                  );
                  return narrow
                      ? Column(children: [
                          horasField,
                          const SizedBox(height: 10),
                          minutosField,
                        ])
                      : Row(children: [
                          Expanded(child: horasField),
                          const SizedBox(width: 12),
                          Expanded(child: minutosField),
                        ]);
                }),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: guardar, child: const Text('Guardar')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (res == true) setState(() {}); // refresca lista si hubo cambios
}


  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('servicios')
        .orderBy('nombre');

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
            color: kPrimary, fontSize: 20, fontWeight: FontWeight.w600,
          ),
          title: const Text('Gestionar servicios'),
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
                    // Barra azul "Servicios" + botón Agregar (responsive)
                    Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                      child: LayoutBuilder(
                        builder: (_, c) {
                          final narrow = c.maxWidth < 440;
                          return Row(
                            children: [
                              const Icon(Icons.build_rounded, color: Colors.white),
                              const SizedBox(width: 8),
                              const Text(
                                'Servicios',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (!narrow)
                                OutlinedButton.icon(
                                  onPressed: () => _showEdit(),
                                  icon: const Icon(Icons.add, size: 18, color: Colors.white),
                                  label: const Text(
                                    'Agregar servicio',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: 'Agregar servicio',
                                  onPressed: () => _showEdit(),
                                  icon: const Icon(Icons.add_circle, color: Colors.white),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Card lista
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(_radius),
                          boxShadow: const [
                            BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))
                          ],
                        ),
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: q.snapshots(),
                          builder: (_, s) {
                            if (s.hasError) return Center(child: Text('Error: ${s.error}'));
                            if (!s.hasData) return const Center(child: CircularProgressIndicator());
                            final docs = s.data!.docs;
                            if (docs.isEmpty) {
                              return const Center(child: Text('Sin servicios. Usá “Agregar servicio”.'));
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final d = docs[i];
                                final x = d.data();
                                final activo = (x['activo'] as bool?) ?? true;
                                final precio = (x['precio'] as num?) ?? 0;
                                final mins = (x['duracion_min'] as num?)?.toInt() ?? 0;

                                return _ServiceItem(
                                  nombre: _titleCase((x['nombre'] ?? '') as String),
                                  precio: _fmtMoney(precio),
                                  duracion: _fmtDurMin(mins),
                                  activo: activo,
                                  onToggleActivo: (v) => d.reference.update({
                                    'activo': v,
                                    'updated_at': FieldValue.serverTimestamp(),
                                  }),
                                  onEdit: () => _showEdit(doc: d),
                                  onDelete: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(_radius)),
                                        title: const Text('Eliminar servicio'),
                                        content: const Text('¿Confirmás eliminar?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
                                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) await d.reference.delete();
                                  },
                                );
                              },
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

// ===== Ítem visual =====
class _ServiceItem extends StatelessWidget {
  final String nombre;
  final String precio;
  final String duracion;
  final bool activo;
  final ValueChanged<bool> onToggleActivo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceItem({
    required this.nombre,
    required this.precio,
    required this.duracion,
    required this.activo,
    required this.onToggleActivo,
    required this.onEdit,
    required this.onDelete,
  });

  static const TextStyle _priceStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6EEF9)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (_, c) {
              final narrow = c.maxWidth < 520;

              final left = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ChipIcon(text: duracion, icon: Icons.timer_outlined),
                        _ChipIcon(
                          text: activo ? 'Activo' : 'Inactivo',
                          icon: activo ? Icons.check_circle : Icons.pause_circle_filled,
                          color: activo ? Colors.green : Colors.orange,
                        ),
                      ],
                    ),
                  ],
                ),
              );

              final price = Padding(
                padding: const EdgeInsets.only(right: 12, left: 12),
                child: Text(precio, style: _priceStyle, overflow: TextOverflow.ellipsis),
              );

              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch.adaptive(value: activo, onChanged: onToggleActivo),
                  IconButton(tooltip: 'Editar', onPressed: onEdit, icon: const Icon(Icons.edit)),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  ),
                ],
              );

              if (!narrow) {
                return Row(children: [left, price, actions]);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [left, price]),
                  const SizedBox(height: 8),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChipIcon extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  const _ChipIcon({required this.text, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}












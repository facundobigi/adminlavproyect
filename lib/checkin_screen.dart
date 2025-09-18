// checkin_screen.dart
import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _formKey = GlobalKey<FormState>();
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  // Paleta y tokens coherentes
  static const Color kPrimary = Color.fromARGB(255, 19, 49, 110);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 640;
  static const double _radius = 16;

  // Datos cliente
  final _nombre = TextEditingController();
  final _dni = TextEditingController();
  final _telefono = TextEditingController();
  final _vehiculo = TextEditingController();

  // Servicio seleccionado
  String? _servicioSelId;
  String? _servicioSelNombre;
  int _durSelMin = 30;
  double _precioSel = 0;

  // Estado
  static const int _CAPACIDAD_PUESTOS = 2;
  bool _saving = false;
  DateTime? _etaCalculada;

  // ------- Helpers -------
  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
  String _cleanSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _capitalizeWord(String w) {
    if (w.isEmpty) return w;
    final first = w.characters.first.toUpperCase();
    final rest = w.characters.skip(1).toList().join().toLowerCase();
    return '$first$rest';
  }
  String _fmtDur(int mins) {
  final h = mins ~/ 60, m = mins % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}


  String _titleCase(String s) =>
      _cleanSpaces(s).split(' ').map((p) => p.split('-').map(_capitalizeWord).join('-')).join(' ');

  // Filtros de entrada
  static final _nombreVehiculoAllow =
      FilteringTextInputFormatter.allow(RegExp(r"[ A-Za-zÁÉÍÓÚÜÑáéíóúüñ'\-]", caseSensitive: false));
  static final _vehiculoAllow =
      FilteringTextInputFormatter.allow(RegExp(r"[ A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9\.\,\/\-]", caseSensitive: false));

  // ------- Clientes (users/{uid}/clientes/{telefono_norm}) -------
  Future<DocumentReference<Map<String, dynamic>>> _upsertCliente({
    required String nombre,
    required String dni,
    required String telefono,
    String? vehiculo,
  }) async {
    final telNorm = _digits(telefono);
    final dniNorm = _digits(dni);
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('clientes')
        .doc(telNorm);

    final snap = await ref.get();
    final now = DateTime.now();

    final base = {
      'nombre': nombre,
      'dni': dni,
      'dni_norm': dniNorm,
      'telefono': telefono,
      'telefono_norm': telNorm,
      'last_visit': now,
    };

    if (snap.exists) {
      await ref.update({
        ...base,
        if (vehiculo?.trim().isNotEmpty == true)
          'vehiculos': FieldValue.arrayUnion([vehiculo!.trim()]),
        'visitas': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set({
        ...base,
        'visitas': 1,
        'vehiculos': vehiculo?.trim().isNotEmpty == true ? [vehiculo!.trim()] : <String>[],
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    return ref;
  }

  final _existeCliente = ValueNotifier<bool>(false);

  Future<void> _buscarClientePorTelefono(String tel) async {
    final telNorm = _digits(tel);
    if (telNorm.length < 7) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('clientes')
        .doc(telNorm);
    final snap = await ref.get();

    if (snap.exists) {
      final c = snap.data()!;
      _nombre.text = (c['nombre'] ?? '') as String;
      _dni.text = (c['dni'] ?? '') as String;
      final vs = (c['vehiculos'] as List?)?.cast<String>() ?? const <String>[];
      if (vs.isNotEmpty && _vehiculo.text.isEmpty) _vehiculo.text = vs.last;
      _existeCliente.value = true;
    } else {
      _existeCliente.value = false;
    }
  }

  // ------- ETA dinámica -------
  Future<void> _calcularETA() async {
    setState(() => _etaCalculada = null);
    final now = DateTime.now();

    // catálogo del usuario
    final catSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('servicios')
        .get();

    final Map<String, int> dur = {
      for (final d in catSnap.docs)
        (d.data()['nombre'] as String): (d.data()['duracion_min'] as num).toInt()
    };

    int trabajoPendienteMin = 0;

    final baseOrdenes = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('ordenes');

    final qCola = await baseOrdenes.where('estado', isEqualTo: 'en_cola').get();
    for (final d in qCola.docs) {
      final nombreSrv = (d['servicio'] ?? '') as String;
      trabajoPendienteMin += (dur[nombreSrv] ?? 40);
    }

    final qLav = await baseOrdenes.where('estado', isEqualTo: 'en_lavado').get();
    for (final d in qLav.docs) {
      final nombreSrv = (d['servicio'] ?? '') as String;
      final total = (dur[nombreSrv] ?? 40);
      final ts = d['started_at'];
      final started = ts is Timestamp ? ts.toDate() : null;
      final rem = started == null
          ? total
          : (total - now.difference(started).inMinutes).clamp(0, total);
      trabajoPendienteMin += rem;
    }

    final esperaMin = (trabajoPendienteMin / _CAPACIDAD_PUESTOS).ceil();
    setState(() {
      _etaCalculada = now.add(Duration(minutes: esperaMin + _durSelMin));
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_servicioSelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un servicio')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final nombreClean = _titleCase(_nombre.text);
      final vehiculoClean = _titleCase(_vehiculo.text);
      final dniClean = _cleanSpaces(_dni.text);
      final telClean = _cleanSpaces(_telefono.text);

      _nombre.text = nombreClean;
      _vehiculo.text = vehiculoClean;
      _dni.text = dniClean;
      _telefono.text = telClean;

      final cliRef = await _upsertCliente(
        nombre: nombreClean,
        dni: dniClean,
        telefono: telClean,
        vehiculo: vehiculoClean,
      );

      final ordenesCol = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('ordenes');

      await ordenesCol.add({
        'clienteRef': cliRef,
        'cliente_snapshot': {
          'nombre': nombreClean,
          'dni': dniClean,
          'telefono': telClean,
        },
        'vehiculo': vehiculoClean,
        'servicio_id': _servicioSelId,
        'servicio': _servicioSelNombre,
        'precio': _precioSel,
        'precio_snapshot': _precioSel,
        'duracion_min_snapshot': _durSelMin,
        'estado': 'en_cola',
        'created_at': FieldValue.serverTimestamp(),
        'promised_at': _etaCalculada != null ? Timestamp.fromDate(_etaCalculada!) : FieldValue.serverTimestamp(),
        'started_at': null,
        'finished_at': null,
        'delivered_at': null,
        'pago': null,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _dni.dispose();
    _telefono.dispose();
    _vehiculo.dispose();
    _existeCliente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serviciosQ = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('servicios')
        .orderBy('nombre')
        .snapshots();

    return Scaffold(
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
        title: const Text('Check-in de cliente'),
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
                      Icon(Icons.person_add_alt_1, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Check-in',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
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
                          offset: Offset(0, 3))
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Datos del cliente',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),

                        // NOMBRE
                        TextFormField(
                          controller: _nombre,
                          decoration: const InputDecoration(
                            labelText: 'Nombre y apellido',
                            hintText: 'Ej: Juan Pérez',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.name,
                          autofillHints: const [AutofillHints.name],
                          inputFormatters: [_nombreVehiculoAllow, LengthLimitingTextInputFormatter(60)],
                          validator: (v) {
                            final s = _cleanSpaces(v ?? '');
                            if (s.length < 3) return 'Ingresá el nombre';
                            if (!s.contains(' ')) return 'Nombre y apellido';
                            return null;
                          },
                          onEditingComplete: () {
                            _nombre.text = _titleCase(_nombre.text);
                            FocusScope.of(context).nextFocus();
                          },
                        ),
                        const SizedBox(height: 12),

                        // DNI
                        TextFormField(
                          controller: _dni,
                          decoration: const InputDecoration(
                            labelText: 'DNI',
                            hintText: 'Solo números',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          validator: (v) {
                            final d = _digits(v ?? '');
                            if (d.isEmpty) return 'Ingresá el DNI';
                            if (d.length < 7 || d.length > 10) return 'DNI inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // TELÉFONO
                        TextFormField(
                          controller: _telefono,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            hintText: 'Solo números',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
                          onChanged: _buscarClientePorTelefono,
                          validator: (v) {
                            final t = _digits(v ?? '');
                            if (t.length < 8 || t.length > 13) return 'Teléfono inválido';
                            return null;
                          },
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: _existeCliente,
                          builder: (_, ok, __) => ok
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text('Cliente encontrado ✓', style: TextStyle(color: Colors.green)),
                                )
                              : const SizedBox.shrink(),
                        ),

                        const SizedBox(height: 20),
                        const Text('Vehículo y servicio',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),

                        // VEHÍCULO
                        TextFormField(
                          controller: _vehiculo,
                          decoration: const InputDecoration(
                            labelText: 'Vehículo (ej: Ford Focus gris)',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [_vehiculoAllow, LengthLimitingTextInputFormatter(60)],
                          validator: (v) => (v == null || _cleanSpaces(v).isEmpty) ? 'Ingresá el vehículo' : null,
                          onEditingComplete: () {
                            _vehiculo.text = _titleCase(_vehiculo.text);
                            FocusScope.of(context).nextFocus();
                          },
                        ),
                        const SizedBox(height: 12),

                        // Servicios del usuario
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: serviciosQ,
                          builder: (_, s) {
                            if (s.hasError) {
                              return Text('Error: ${s.error}', style: const TextStyle(color: Colors.red));
                            }
                            if (!s.hasData) {
                              return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
                            }
                            final allDocs = s.data!.docs;
                            final docs = allDocs.where((d) => (d.data()['activo'] as bool?) ?? true).toList();

                            if (docs.isEmpty) {
                              return const Text('No hay servicios activos. Cargalos en "Gestionar servicios".');
                            }

                            if (_servicioSelId == null) {
                              final x = docs.first.data();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(() {
                                  _servicioSelId = docs.first.id;
                                  _servicioSelNombre = x['nombre'] as String;
                                  _durSelMin = (x['duracion_min'] as num).toInt();
                                  _precioSel = (x['precio'] as num).toDouble();
                                });
                                _calcularETA();
                              });
                            }

                            return DropdownButtonFormField<String>(
                              value: _servicioSelId,
                              items: docs
                                  .map((d) => DropdownMenuItem(
                                        value: d.id,
                                        child: Text((d.data()['nombre'] ?? '') as String),
                                      ))
                                  .toList(),
                              onChanged: (id) {
                                final d = docs.firstWhere((e) => e.id == id);
                                final x = d.data();
                                setState(() {
                                  _servicioSelId = d.id;
                                  _servicioSelNombre = x['nombre'] as String;
                                  _durSelMin = (x['duracion_min'] as num).toInt();
                                  _precioSel = (x['precio'] as num).toDouble();
                                });
                                _calcularETA();
                              },
                              decoration: const InputDecoration(labelText: 'Servicio', border: OutlineInputBorder()),
                              validator: (v) => v == null ? 'Seleccioná un servicio' : null,
                            );
                          },
                        ),

                        const SizedBox(height: 8),
                        Row(
  children: [
    const Icon(Icons.schedule, size: 18),
    const SizedBox(width: 6),
    Text('TE: ${_fmtDur(_durSelMin)}'),
    const Spacer(),
    Text('Precio: \$${_precioSel.toStringAsFixed(0)}'),
  ],
),


                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              elevation: 0,
                            ),
                            onPressed: _saving ? null : _guardar,
                            child: _saving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Crear orden'),
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






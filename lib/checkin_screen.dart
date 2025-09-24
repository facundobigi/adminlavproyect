// checkin_screen.dart
import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CheckInScreen extends StatefulWidget {
  final String tenantId; // UID del dueño
  final String role;     // 'admin' | 'operator'
  const CheckInScreen({super.key, required this.tenantId, required this.role});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _formKey = GlobalKey<FormState>();

  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 19, 49, 110);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 640;
  static const double _radius = 16;

  // Datos cliente
  final _telefono = TextEditingController();
  final _patente = TextEditingController();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _vehiculo = TextEditingController();

  // Servicio seleccionado
  String? _servicioSelId;
  String? _servicioSelNombre;
  int _durSelMin = 30;
  double _precioSel = 0;

  // Estado
  bool _saving = false;
  DateTime? _etaCalculada;
  final _existeCliente = ValueNotifier<bool>(false);
  final _patentesPrevias = ValueNotifier<List<String>>(<String>[]);
  final _vehiculosPrevios = ValueNotifier<List<String>>(<String>[]);

  // ===== Helpers =====
  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
  String _cleanSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _capitalizeWord(String w) {
    if (w.isEmpty) return w;
    final first = w.characters.first.toUpperCase();
    final rest = w.characters.skip(1).toList().join().toLowerCase();
    return '$first$rest';
  }

  String _titleCase(String s) =>
      _cleanSpaces(s).split(' ').map((p) => p.split('-').map(_capitalizeWord).join('-')).join(' ');

  String _fmtDur(int mins) {
    final h = mins ~/ 60, m = mins % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  // Normalización patente
  String _normPatente(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // Patrones AR
  final _reMercosur = RegExp(r'^[A-HJ-NP-Z]{2}\d{3}[A-HJ-NP-Z]{2}$'); // AA999AA
  final _reVieja = RegExp(r'^[A-HJ-NP-Z]{3}\d{3}$');                  // AAA999
  bool _validPatenteAR(String p) {
    final n = _normPatente(p);
    if (n.length < 6 || n.length > 7) return false;
    return _reMercosur.hasMatch(n) || _reVieja.hasMatch(n);
  }

  // Filtros
  static final _nombreAllow =
      FilteringTextInputFormatter.allow(RegExp(r"[ A-Za-zÁÉÍÓÚÜÑáéíóúüñ'\-]", caseSensitive: false));
  static final _vehiculoAllow =
      FilteringTextInputFormatter.allow(RegExp(r"[ A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9\.\,\/\-]", caseSensitive: false));
  static final _patenteAllow = FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9 \-]"));

  // ===== Clientes =====
  Future<DocumentReference<Map<String, dynamic>>> _upsertCliente({
    required String telefono,
    required String nombre,
    required String apellido,
    required String? patente,
    required String? vehiculo,
  }) async {
    final telNorm = _digits(telefono);
    final ref = FirebaseFirestore.instance
        .collection('users').doc(widget.tenantId)
        .collection('clientes').doc(telNorm);

    final now = DateTime.now();
    final nombreCompleto = _cleanSpaces('$nombre $apellido');

    final snap = await ref.get();

    final base = {
      'telefono': telefono,
      'telefono_norm': telNorm,
      'nombre': _titleCase(nombre),
      'apellido': _titleCase(apellido),
      'nombre_completo': _titleCase(nombreCompleto),
      'last_visit': now,
    };

    final updates = <String, dynamic>{
      ...base,
      'updated_at': FieldValue.serverTimestamp(),
      if (vehiculo != null && vehiculo.trim().isNotEmpty)
        'vehiculos': FieldValue.arrayUnion([_titleCase(vehiculo.trim())]),
      if (patente != null && patente.trim().isNotEmpty) ...{
        'patentes': FieldValue.arrayUnion([_normPatente(patente)]),
        'last_patente': _normPatente(patente),
      },
      if (vehiculo != null && vehiculo.trim().isNotEmpty) 'last_vehiculo': _titleCase(vehiculo.trim()),
      'visitas': FieldValue.increment(1),
    };

    if (snap.exists) {
      await ref.update(updates);
    } else {
      await ref.set({
        ...base,
        'created_at': FieldValue.serverTimestamp(),
        'visitas': 1,
        'vehiculos': vehiculo?.trim().isNotEmpty == true ? [_titleCase(vehiculo!.trim())] : <String>[],
        'patentes': patente?.trim().isNotEmpty == true ? [_normPatente(patente!)] : <String>[],
        if (patente?.trim().isNotEmpty == true) 'last_patente': _normPatente(patente!),
        if (vehiculo?.trim().isNotEmpty == true) 'last_vehiculo': _titleCase(vehiculo!.trim()),
      });
    }
    return ref;
  }

  Future<void> _buscarClientePorTelefono(String tel) async {
    final telNorm = _digits(tel);
    if (telNorm.length < 8) return;

    final ref = FirebaseFirestore.instance
        .collection('users').doc(widget.tenantId)
        .collection('clientes').doc(telNorm);
    final snap = await ref.get();
    if (!mounted) return;

    if (!snap.exists) {
      _existeCliente.value = false;
      _patentesPrevias.value = <String>[];
      _vehiculosPrevios.value = <String>[];
      return;
    }

    final c = snap.data()!;
    String nombre = (c['nombre'] ?? '') as String;
    String apellido = (c['apellido'] ?? '') as String;
    if (nombre.isEmpty && apellido.isEmpty) {
      final full = (c['nombre_completo'] ?? '') as String;
      final parts = _cleanSpaces(full).split(' ');
      if (parts.length >= 2) {
        nombre = parts.sublist(0, parts.length - 1).join(' ');
        apellido = parts.last;
      } else {
        nombre = full;
      }
    }

    _nombre.text = _titleCase(nombre);
    _apellido.text = _titleCase(apellido);

    final vs = (c['vehiculos'] as List?)?.cast<String>() ?? const <String>[];
    final ps = (c['patentes'] as List?)?.cast<String>() ?? const <String>[];

    _vehiculosPrevios.value = vs;
    _patentesPrevias.value = ps;

    if (_vehiculo.text.isEmpty && vs.isNotEmpty) _vehiculo.text = vs.last;
    if (_patente.text.isEmpty && (c['last_patente'] is String)) _patente.text = (c['last_patente'] as String);

    _existeCliente.value = true;
  }

  // ===== ETA =====
  Future<void> _calcularETA() async {
    if (!mounted) return;
    setState(() => _etaCalculada = null);
    final now = DateTime.now();
    if (!mounted) return;
    setState(() => _etaCalculada = now.add(Duration(minutes: _durSelMin)));
  }

  // ===== Guardar =====
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_servicioSelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleccioná un servicio')));
      return;
    }
    setState(() => _saving = true);

    try {
      final telClean = _cleanSpaces(_telefono.text);
      final nombreClean = _titleCase(_nombre.text);
      final apellidoClean = _titleCase(_apellido.text);
      final vehiculoClean = _titleCase(_vehiculo.text);
      final patenteRaw = _patente.text.trim().toUpperCase();
      final patenteNorm = _normPatente(patenteRaw);

      final cliRef = await _upsertCliente(
        telefono: telClean,
        nombre: nombreClean,
        apellido: apellidoClean,
        patente: patenteRaw.isEmpty ? null : patenteRaw,
        vehiculo: vehiculoClean.isEmpty ? null : vehiculoClean,
      );

      final ordenesCol = FirebaseFirestore.instance
          .collection('users').doc(widget.tenantId).collection('ordenes');

      await ordenesCol.add({
        'clienteRef': cliRef,
        'cliente_snapshot': {
          'nombre': nombreClean,
          'apellido': apellidoClean,
          'nombre_completo': _cleanSpaces('$nombreClean $apellidoClean'),
          'telefono': telClean,
        },
        'vehiculo': vehiculoClean,
        'patente': patenteRaw.isEmpty ? null : patenteRaw,
        'patente_norm': patenteNorm.isEmpty ? null : patenteNorm,
        'servicio_id': _servicioSelId,
        'servicio': _servicioSelNombre,
        'precio': _precioSel,
        'precio_snapshot': _precioSel,
        'duracion_min_snapshot': _durSelMin,
        'estado': 'en_cola',
        'created_at': FieldValue.serverTimestamp(),
        'promised_at': _etaCalculada != null
            ? Timestamp.fromDate(_etaCalculada!)
            : FieldValue.serverTimestamp(),
        'started_at': null,
        'finished_at': null,
        'delivered_at': null,
        'pago': null,
        'tenant_id': widget.tenantId,
        'created_by_role': widget.role,
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
    _telefono.dispose();
    _patente.dispose();
    _nombre.dispose();
    _apellido.dispose();
    _vehiculo.dispose();
    _existeCliente.dispose();
    _patentesPrevias.dispose();
    _vehiculosPrevios.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serviciosQ = FirebaseFirestore.instance
        .collection('users').doc(widget.tenantId)
        .collection('servicios')
        .orderBy('nombre')
        .snapshots();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: kPrimary),
        titleTextStyle: const TextStyle(color: kPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        title: const Text('Check-in de cliente'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _panelMaxW),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            // ✅ Scroll para evitar overflow (incluye espacio por teclado)
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barra azul
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(_radius)),
                    child: const Row(
                      children: [
                        Icon(Icons.person_add_alt_1, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Check-in', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(_radius),
                      boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Identificación y datos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(13),
                            ],
                            onChanged: _buscarClientePorTelefono,
                            validator: (v) {
                              final t = _digits(v ?? '');
                              if (t.length < 8 || t.length > 13) return 'Teléfono inválido';
                              return null;
                            },
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: _existeCliente,
                            builder: (_, ok, __) => AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: ok
                                  ? const Padding(
                                      key: ValueKey('ok'),
                                      padding: EdgeInsets.only(top: 6),
                                      child: Text('Cliente encontrado ✓', style: TextStyle(color: Colors.green)),
                                    )
                                  : const SizedBox.shrink(key: ValueKey('empty')),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // NOMBRE y APELLIDO (con espacio de error reservado para evitar desniveles)
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _nombre,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre',
                                    counterText: '',
                                    border: OutlineInputBorder(),
                                    helperText: ' ',         // ✅ reserva espacio
                                    errorMaxLines: 1,
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.name,
                                  autofillHints: const [AutofillHints.givenName],
                                  inputFormatters: [_nombreAllow, LengthLimitingTextInputFormatter(40)],
                                  validator: (v) {
                                    final s = _cleanSpaces(v ?? '');
                                    if (s.length < 2) return 'Ingresá el nombre';
                                    return null;
                                  },
                                  onEditingComplete: () {
                                    _nombre.text = _titleCase(_nombre.text);
                                    FocusScope.of(context).nextFocus();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _apellido,
                                  decoration: const InputDecoration(
                                    labelText: 'Apellido',
                                    counterText: '',
                                    border: OutlineInputBorder(),
                                    helperText: ' ',         // ✅ reserva espacio
                                    errorMaxLines: 1,
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  keyboardType: TextInputType.name,
                                  autofillHints: const [AutofillHints.familyName],
                                  inputFormatters: [_nombreAllow, LengthLimitingTextInputFormatter(40)],
                                  validator: (v) {
                                    final s = _cleanSpaces(v ?? '');
                                    if (s.length < 2) return 'Ingresá el apellido';
                                    return null;
                                  },
                                  onEditingComplete: () {
                                    _apellido.text = _titleCase(_apellido.text);
                                    FocusScope.of(context).nextFocus();
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                          const Text('Vehículo y servicio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),

                          // VEHÍCULO
                          TextFormField(
                            controller: _vehiculo,
                            decoration: const InputDecoration(
                              labelText: 'Vehículo (ej: Ford Focus gris)',
                              counterText: '',
                              border: OutlineInputBorder(),
                              helperText: ' ', // mantiene altura pareja si hay error
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
                          const SizedBox(height: 4),

                          // Chips vehículos previos
                          ValueListenableBuilder<List<String>>(
                            valueListenable: _vehiculosPrevios,
                            builder: (_, list, __) {
                              final safe = list ?? <String>[];
                              if (safe.isEmpty) return const SizedBox.shrink();
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: safe.map((v) {
                                  return ActionChip(
                                    label: Text(v),
                                    onPressed: () => setState(() => _vehiculo.text = v),
                                  );
                                }).toList(),
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // PATENTE
                          TextFormField(
                            controller: _patente,
                            decoration: const InputDecoration(
                              labelText: 'Patente',
                              hintText: 'Ej: AB123CD o ABC123',
                              counterText: '',
                              border: OutlineInputBorder(),
                              helperText: ' ',
                            ),
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [_patenteAllow, LengthLimitingTextInputFormatter(8)],
                            onChanged: (s) {
                              final up = s.toUpperCase();
                              if (s != up) {
                                final sel = _patente.selection;
                                _patente.value = TextEditingValue(text: up, selection: sel);
                              }
                            },
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Ingresá la patente';
                              if (!_validPatenteAR(s)) return 'Formato inválido (AB123CD o ABC123)';
                              return null;
                            },
                          ),
                          const SizedBox(height: 4),

                          // Chips patentes previas
                          ValueListenableBuilder<List<String>>(
                            valueListenable: _patentesPrevias,
                            builder: (_, list, __) {
                              final safe = list ?? <String>[];
                              if (safe.isEmpty) return const SizedBox.shrink();
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: safe.map((p) {
                                  return ActionChip(
                                    label: Text(p),
                                    onPressed: () => setState(() => _patente.text = p),
                                  );
                                }).toList(),
                              );
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                elevation: 0,
                              ),
                              onPressed: _saving ? null : _guardar,
                              child: _saving
                                  ? const SizedBox(
                                      width: 24, height: 24,
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
      ),
    );
  }
}









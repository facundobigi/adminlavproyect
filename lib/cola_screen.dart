// cola_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ColaScreen extends StatefulWidget {
  const ColaScreen({super.key});
  @override
  State<ColaScreen> createState() => _ColaScreenState();
}

class _ColaScreenState extends State<ColaScreen> {
  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 21, 53, 117);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 920;
  static const double _radius = 16;

  static const int _CAPACIDAD_PUESTOS = 4;

  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  Timer? _tick;
  DateTime _now = DateTime.now();

  final Map<String, int> _durByName = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _enColaDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _enLavDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _puestosDocs = [];

  final Map<String, DateTime> _etaEndNow = {};
  final Set<String> _busy = {};

  CollectionReference<Map<String, dynamic>> get _ordenesCol =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection('ordenes');
  CollectionReference<Map<String, dynamic>> get _puestosCol =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection('puestos');
  CollectionReference<Map<String, dynamic>> get _serviciosCol =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection('servicios');

  bool _isBusy(String id) => _busy.contains(id);
  Future<void> _guard(Future<void> Function() f, String id) async {
    if (_busy.contains(id)) return;
    _busy.add(id);
    if (mounted) setState(() {});
    try {
      await f();
    } finally {
      _busy.remove(id);
      if (mounted) setState(() {});
    }
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  Map<String, dynamic> _asMapDyn(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _duracionDeOrden(Map<String, dynamic> x) {
    final snap = (x['duracion_min_snapshot'] as num?)?.toInt();
    if (snap != null && snap > 0) return snap;
    final srv = (x['servicio'] ?? '') as String;
    return _durByName[srv] ?? 40;
  }

  String _fmtMMSS(int secs) {
    if (secs < 0) secs = 0;
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _hayPuestos => _puestosDocs.isNotEmpty;

  bool get _hayPuestoLibre {
    if (_hayPuestos) {
      for (final d in _puestosDocs) {
        final x = d.data();
        if (x['ordenId'] == null) return true;
      }
      return false;
    }
    return _enLavDocs.length < _CAPACIDAD_PUESTOS;
  }

  int get _libresCount {
    if (_hayPuestos) {
      int c = 0;
      for (final d in _puestosDocs) {
        final x = d.data();
        if (x['ordenId'] == null) c++;
      }
      return c;
    }
    return (_CAPACIDAD_PUESTOS - _enLavDocs.length).clamp(0, _CAPACIDAD_PUESTOS);
  }

  @override
  void initState() {
    super.initState();

    _serviciosCol.where('activo', isEqualTo: true).snapshots().listen((s) {
      _durByName
        ..clear()
        ..addAll({
          for (final d in s.docs)
            (d.data()['nombre'] as String):
                (d.data()['duracion_min'] as num).toInt()
        });
      _recomputeEtaNow();
      if (mounted) setState(() {});
    });

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _now = DateTime.now();
      _recomputeEtaNow();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _recomputeEtaNow() {
    final disponibles = <DateTime>[];

    if (_hayPuestos) {
      for (final d in _puestosDocs) {
        final x = d.data();
        final endsAt = _toDate(x['ends_at']);
        disponibles.add(endsAt ?? _now);
      }
      if (disponibles.isEmpty) {
        for (int i = 0; i < _CAPACIDAD_PUESTOS; i++) {
          disponibles.add(_now);
        }
      }
    } else {
      final enLavFines = _enLavDocs.map((d) {
        final x = d.data();
        final total = _duracionDeOrden(x);
        final started = _toDate(x['started_at']) ?? _now;
        return started.add(Duration(minutes: total));
      }).toList()
        ..sort();
      disponibles.addAll(enLavFines);
      while (disponibles.length < _CAPACIDAD_PUESTOS) {
        disponibles.add(_now);
      }
    }

    _etaEndNow.clear();

    final ordenados = [..._enColaDocs]
      ..sort((a, b) {
        final ad = _toDate(a.data()['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd = _toDate(b.data()['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

    for (final d in ordenados) {
      disponibles.sort();
      final inicio =
          disponibles.first.isBefore(_now) ? _now : disponibles.first;
      final total = _duracionDeOrden(d.data());
      final fin = inicio.add(Duration(minutes: total));
      _etaEndNow[d.id] = fin;
      disponibles[0] = fin;
    }
  }

  Future<void> _iniciarOrden(
      QueryDocumentSnapshot<Map<String, dynamic>> ordenDoc) async {
    final ordenRef = ordenDoc.reference;

    if (_hayPuestos) {
      final libres = await _puestosCol.where('ordenId', isNull: true).limit(1).get();
      if (libres.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin puestos libres')),
          );
        }
        return;
      }
      final puestoRef = libres.docs.first.reference;

      await FirebaseFirestore.instance.runTransaction((t) async {
        final pSnap = await t.get(puestoRef);
        final pData = pSnap.data();
        if (pData != null && pData['ordenId'] != null) {
          throw Exception('OCUPADO');
        }

        final oSnap = await t.get(ordenRef);
        final oData = oSnap.data();
        if (oData == null || oData['estado'] != 'en_cola') {
          throw Exception('NO_EN_COLA');
        }

        t.update(ordenRef, {
          'estado': 'en_lavado',
          'puesto': puestoRef.id,
          'started_at': FieldValue.serverTimestamp(),
        });
      }).catchError((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Puesto ocupado, reintentá')),
          );
        }
      });

      final x = ordenDoc.data();
      final mins = _duracionDeOrden(x);
      final endsAt = DateTime.now().add(Duration(minutes: mins));
      await puestoRef.update({
        'ordenId': ordenRef.id,
        'ends_at': Timestamp.fromDate(endsAt),
      });
    } else {
      if (_enLavDocs.length >= _CAPACIDAD_PUESTOS) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Capacidad completa')),
          );
        }
        return;
      }
      await ordenRef.update({
        'estado': 'en_lavado',
        'puesto': null,
        'started_at': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _marcarListo(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final x = doc.data();
    final puestoId = (x['puesto'] ?? '') as String?;
    if (_hayPuestos && puestoId != null && puestoId.isNotEmpty) {
      final puestoRef = _puestosCol.doc(puestoId);
      await FirebaseFirestore.instance.runTransaction((t) async {
        t.update(doc.reference, {
          'estado': 'listo',
          'finished_at': FieldValue.serverTimestamp(),
          'puesto': null,
        });
        t.update(puestoRef, {'ordenId': null, 'ends_at': null});
      });
    } else {
      await doc.reference.update({
        'estado': 'listo',
        'finished_at': FieldValue.serverTimestamp(),
        'puesto': null,
      });
    }
  }

  Future<void> _entregarYCobrar(
    BuildContext ctx,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final x = doc.data();
    final ctrlMonto = TextEditingController(
      text: (x['precio'] as num?)?.toStringAsFixed(0) ?? '',
    );
    String tipo = 'efectivo';

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cobro y entrega'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: tipo,
            items: const [
              DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
              DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
            ],
            onChanged: (v) => tipo = v ?? 'efectivo',
            decoration: const InputDecoration(labelText: 'Medio de pago'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrlMonto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monto'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;

    final monto = double.tryParse(ctrlMonto.text.trim()) ?? 0;
    await doc.reference.update({
      'estado': 'entregado',
      'delivered_at': FieldValue.serverTimestamp(),
      'pago': {'tipo': tipo, 'monto': monto},
    });
  }

  Color _stateColor(String e) {
    switch (e) {
      case 'en_cola':
        return const Color(0xFFF59E0B);
      case 'en_lavado':
        return const Color(0xFF3B82F6);
      case 'listo':
        return const Color(0xFF10B981);
      default:
        return Colors.grey;
    }
  }

  Widget _stateChip(String e) {
    final map = {
      'en_cola': 'En cola',
      'en_lavado': 'En lavado',
      'listo': 'Listo',
      'entregado': 'Entregado',
    };
    final txt = map[e] ?? e;
    final c = _stateColor(e);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.10),
        border: Border.all(color: c.withOpacity(.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(txt, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _orderCard(
    QueryDocumentSnapshot<Map<String, dynamic>> d, {
    required bool hayLibre,
  }) {
    final x = d.data();
    final cli = _asMapDyn(x['cliente_snapshot'] ?? x['cliente'] ?? {});
    final nombre = (cli['nombre'] ?? '') as String;
    final tel = (cli['telefono'] ?? '') as String;
    final veh = (x['vehiculo'] ?? '') as String;
    final srv = (x['servicio'] ?? '') as String;
    final estado = (x['estado'] ?? '') as String;

    int? secs;
    String timeLabel = '';
    if (estado == 'en_cola') {
      final fin = _etaEndNow[d.id];
      secs = fin != null ? fin.difference(_now).inSeconds : null;
      timeLabel = 'Comienza en';
    } else if (estado == 'en_lavado') {
      final start = _toDate(x['started_at']) ?? _now;
      secs = _now.difference(start).inSeconds;
      timeLabel = 'En lavado';
    } else if (estado == 'listo') {
      final fin = _toDate(x['finished_at']) ?? _now;
      secs = _now.difference(fin).inSeconds;
      timeLabel = 'Esperando';
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6EEF9)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Info principal
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$nombre • $veh',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.local_car_wash, size: 14, color: kPrimary),
                        const SizedBox(width: 4),
                        Text(srv, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        const SizedBox(width: 10),
                        Icon(Icons.phone, size: 14, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(tel, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(width: 10),
                        _stateChip(estado),
                      ],
                    ),
                    if (secs != null) ...[
                      const SizedBox(height: 4),
                      Text('$timeLabel: ${_fmtMMSS(secs)}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
              // Acciones
              if (estado == 'en_cola')
                ElevatedButton.icon(
                  onPressed: (!hayLibre || _isBusy(d.id)) ? null : () => _guard(() => _iniciarOrden(d), d.id),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Iniciar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              if (estado == 'en_lavado')
                ElevatedButton.icon(
                  onPressed: _isBusy(d.id) ? null : () => _guard(() => _marcarListo(d), d.id),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Listo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              if (estado == 'listo')
                OutlinedButton.icon(
                  onPressed: _isBusy(d.id) ? null : () => _guard(() => _entregarYCobrar(context, d), d.id),
                  icon: const Icon(Icons.attach_money, size: 18),
                  label: const Text('Cobrar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimary,
                    side: const BorderSide(color: kPrimary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colaQ = _ordenesCol
        .where('estado', isEqualTo: 'en_cola')
        .orderBy('created_at', descending: true);

    final enLavQ = _ordenesCol
        .where('estado', isEqualTo: 'en_lavado')
        .orderBy('started_at', descending: true);

    final listosQ = _ordenesCol
        .where('estado', isEqualTo: 'listo')
        .orderBy('finished_at', descending: true);

    final puestosStream = _puestosCol.snapshots();

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
        title: const Text('Cola de trabajo'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: puestosStream,
        builder: (_, sp) {
          if (sp.hasError) {
            return Center(child: Text('Error: ${sp.error}', style: const TextStyle(color: Colors.red)));
          }
          _puestosDocs = sp.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          _recomputeEtaNow();
          final hayLibre = _hayPuestoLibre;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _panelMaxW),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Barra azul + puestos libres
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.playlist_add_check, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text('Cola de trabajo',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hayLibre ? Icons.check_circle : Icons.block,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Puestos libres: ${_libresCount.toString()}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // En cola
                    _SectionCard(
                      title: 'En cola',
                      icon: Icons.hourglass_bottom,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: colaQ.snapshots(),
                        builder: (_, s) {
                          if (s.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Error: ${s.error}', style: const TextStyle(color: Colors.red)),
                            );
                          }
                          if (!s.hasData) {
                            return const SizedBox(height: 64, child: Center(child: CircularProgressIndicator()));
                          }
                          _enColaDocs = s.data!.docs;
                          _recomputeEtaNow();
                          if (_enColaDocs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('Sin autos en cola'),
                            );
                          }
                          return Column(
                            children: _enColaDocs
                                .map((d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _orderCard(d, hayLibre: hayLibre),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // En lavado
                    _SectionCard(
                      title: 'En lavado',
                      icon: Icons.local_car_wash,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: enLavQ.snapshots(),
                        builder: (_, s) {
                          if (s.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Error: ${s.error}', style: const TextStyle(color: Colors.red)),
                            );
                          }
                          if (!s.hasData) {
                            return const SizedBox(height: 64, child: Center(child: CircularProgressIndicator()));
                          }
                          _enLavDocs = s.data!.docs;
                          _recomputeEtaNow();
                          if (_enLavDocs.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('—'),
                            );
                          }
                          return Column(
                            children: _enLavDocs
                                .map((d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _orderCard(d, hayLibre: hayLibre),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Para retirar
                    _SectionCard(
                      title: 'Para retirar',
                      icon: Icons.check_circle,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: listosQ.snapshots(),
                        builder: (_, s) {
                          if (s.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Error: ${s.error}', style: const TextStyle(color: Colors.red)),
                            );
                          }
                          if (!s.hasData) {
                            return const SizedBox(height: 64, child: Center(child: CircularProgressIndicator()));
                          }
                          final items = s.data!.docs;
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text('—'),
                            );
                          }
                          return Column(
                            children: items
                                .map((d) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _orderCard(d, hayLibre: hayLibre),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_ColaScreenState._radius),
        boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Icon(icon, color: _ColaScreenState.kPrimary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEAECEF)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }
}














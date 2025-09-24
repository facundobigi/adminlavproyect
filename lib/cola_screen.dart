// cola_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ColaScreen extends StatefulWidget {
  final String tenantId; // UID del dueño
  final String role;     // 'admin' | 'operator'
  const ColaScreen({super.key, required this.tenantId, required this.role});

  @override
  State<ColaScreen> createState() => _ColaScreenState();
}

class _ColaScreenState extends State<ColaScreen> {
  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 21, 53, 117);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 1200;
  static const double _radius = 16;

  Timer? _tick;
  DateTime _now = DateTime.now();

  final Map<String, int> _durByName = {};
  final Set<String> _busy = {};

  CollectionReference<Map<String, dynamic>> get _ordenesCol =>
      FirebaseFirestore.instance.collection('users').doc(widget.tenantId).collection('ordenes');
  CollectionReference<Map<String, dynamic>> get _serviciosCol =>
      FirebaseFirestore.instance.collection('users').doc(widget.tenantId).collection('servicios');

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

  @override
  void initState() {
    super.initState();

    _serviciosCol.where('activo', isEqualTo: true).snapshots().listen((s) {
      _durByName
        ..clear()
        ..addAll({
          for (final d in s.docs)
            (d.data()['nombre'] as String): (d.data()['duracion_min'] as num).toInt()
        });
      if (mounted) setState(() {});
    });

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _now = DateTime.now();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _iniciarOrden(QueryDocumentSnapshot<Map<String, dynamic>> ordenDoc) async {
    final ref = ordenDoc.reference;
    await FirebaseFirestore.instance.runTransaction((t) async {
      final snap = await t.get(ref);
      final x = snap.data();
      if (x == null || x['estado'] != 'en_cola') {
        throw Exception('NO_EN_COLA');
      }
      t.update(ref, {
        'estado': 'en_lavado',
        'started_at': FieldValue.serverTimestamp(),
        'puesto': null,
      });
    }).catchError((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo iniciar, reintentá')),
        );
      }
    });
  }

  Future<void> _marcarListo(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    await doc.reference.update({
      'estado': 'listo',
      'finished_at': FieldValue.serverTimestamp(),
      'puesto': null,
    });
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
              DropdownMenuItem(value: 'otro', child: Text('Otro')),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        border: Border.all(color: c.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(txt, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _orderCard(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data();
    final cli = _asMapDyn(x['cliente_snapshot'] ?? x['cliente'] ?? {});
    final nombre = (cli['nombre'] ?? '') as String;
    final apellido = (cli['apellido'] ?? '') as String;
    final nombreCompleto = [nombre, apellido].where((e) => (e).trim().isNotEmpty).join(' ').trim().isEmpty
        ? ((cli['nombre_completo'] ?? '') as String)
        : '$nombre $apellido';
    final tel = (cli['telefono'] ?? '') as String;
    final veh = (x['vehiculo'] ?? '') as String;
    final patente = (x['patente'] ?? '') as String;
    final srv = (x['servicio'] ?? '') as String;
    final estado = (x['estado'] ?? '') as String;
    final totalMin = _duracionDeOrden(x);

    int? secs;
    String timeLabel = '';
    if (estado == 'en_lavado') {
      final start = _toDate(x['started_at']) ?? _now;
      secs = _now.difference(start).inSeconds;
      timeLabel = 'Iniciado';
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
                    Text(
                      patente.trim().isEmpty ? '$nombreCompleto • $veh' : '$nombreCompleto • $patente • $veh',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.local_car_wash, size: 14, color: kPrimary),
                          const SizedBox(width: 4),
                          Text(srv, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        ]),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.phone, size: 14, color: Colors.black45),
                          const SizedBox(width: 4),
                          Text(tel, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ]),
                        if (patente.trim().isNotEmpty)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.numbers, size: 14, color: Colors.black45),
                            const SizedBox(width: 4),
                            Text(patente, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          ]),
                        _stateChip(estado),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('TE: ${_fmtMMSS(totalMin * 60)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    if (secs != null) ...[
                      const SizedBox(height: 4),
                      Text('$timeLabel: ${_fmtMMSS(secs)}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Acciones
              if (estado == 'en_cola')
                _btnPrimary(
                  icon: Icons.play_arrow,
                  label: 'Iniciar',
                  onTap: _isBusy(d.id) ? null : () => _guard(() => _iniciarOrden(d), d.id),
                ),
              if (estado == 'en_lavado')
                _btnSuccess(
                  icon: Icons.check_circle,
                  label: 'Listo',
                  onTap: _isBusy(d.id) ? null : () => _guard(() => _marcarListo(d), d.id),
                ),
              if (estado == 'listo')
                _btnOutline(
                  icon: Icons.attach_money,
                  label: 'Cobrar',
                  onTap: _isBusy(d.id) ? null : () => _guard(() => _entregarYCobrar(context, d), d.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colaQ = _ordenesCol.where('estado', isEqualTo: 'en_cola').orderBy('created_at', descending: true);
    final enLavQ = _ordenesCol.where('estado', isEqualTo: 'en_lavado').orderBy('started_at', descending: true);
    final listosQ = _ordenesCol.where('estado', isEqualTo: 'listo').orderBy('finished_at', descending: true);

    final textScaler = MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
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
          title: const Text('Cola de trabajo'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (_, c) {
              final padH = c.maxWidth >= 900 ? 24.0 : 16.0;

              Widget section(
                String title,
                IconData icon,
                Stream<QuerySnapshot<Map<String, dynamic>>> stream, {
                String empty = '—',
              }) {
                return _SectionCard(
                  title: title,
                  icon: icon,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: stream,
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
                      final docs = s.data!.docs;
                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(empty),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _orderCard(docs[i]),
                      );
                    },
                  ),
                );
              }

              final enColaW = section('En cola', Icons.hourglass_bottom, colaQ.snapshots(), empty: 'Sin autos en cola');
              final enLavW = section('En lavado', Icons.local_car_wash, enLavQ.snapshots(), empty: '—');
              final listosW = section('Para retirar', Icons.check_circle, listosQ.snapshots(), empty: '—');

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _panelMaxW),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padH, 16, padH, 16),
                    child: SingleChildScrollView(
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
                                Icon(Icons.playlist_add_check, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Cola de trabajo',
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Apilado
                          enColaW,
                          const SizedBox(height: 12),
                          enLavW,
                          const SizedBox(height: 12),
                          listosW,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Botones
  Widget _btnPrimary({required IconData icon, required String label, VoidCallback? onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(112, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _btnSuccess({required IconData icon, required String label, VoidCallback? onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(112, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _btnOutline({required IconData icon, required String label, VoidCallback? onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: const BorderSide(color: kPrimary),
        minimumSize: const Size(112, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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



















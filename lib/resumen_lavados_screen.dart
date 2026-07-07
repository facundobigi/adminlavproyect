// resumen_lavados_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'patente_utils.dart';

class ResumenLavadosScreen extends StatefulWidget {
  const ResumenLavadosScreen({super.key});
  @override
  State<ResumenLavadosScreen> createState() => _ResumenLavadosScreenState();
}

class _ResumenLavadosScreenState extends State<ResumenLavadosScreen> {
  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 21, 54, 119);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 1140;
  static const double _radius = 16;

  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  late final CollectionReference<Map<String, dynamic>> _ordenesCol =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('ordenes');
  late final CollectionReference<Map<String, dynamic>> _serviciosCol =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('servicios');

  // Filtros
  DateTimeRange _range = DateTimeRange(
    start:
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
        .add(const Duration(days: 1)),
  );
  String _pago = 'todos'; // todos | efectivo | transferencia | otro
  String _servicio = 'todos'; // nombre de servicio o 'todos'
  final _buscaCtrl = TextEditingController();

  // Datos
  bool _loading = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _all = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = [];

  // KPIs
  int kLavados = 0;
  double kIngresos = 0, kEfec = 0, kTransf = 0;
  Duration kEsperaProm = Duration.zero, kLavadoProm = Duration.zero;

  final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$');

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ===== Consultas =====
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> q = _ordenesCol
        .where('finished_at', isGreaterThanOrEqualTo: _range.start)
        .where('finished_at', isLessThan: _range.end);

    if (_pago != 'todos') q = q.where('pago.tipo', isEqualTo: _pago);
    if (_servicio != 'todos') q = q.where('servicio', isEqualTo: _servicio);

    return q.orderBy('finished_at', descending: true);
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final qs = await _buildQuery().limit(500).get();
      _all = qs.docs;
      _aplicarBusqueda();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _aplicarBusqueda() {
    final q = _buscaCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _items = List.of(_all);
    } else {
      _items = _all.where((d) {
        final x = d.data();
        final cli = (x['cliente_snapshot'] ?? {}) as Map<String, dynamic>;
        final s = [
          (cli['nombre'] ?? '').toString(),
          (cli['apellido'] ?? '').toString(),
          (cli['nombre_completo'] ?? '').toString(),
          (cli['telefono'] ?? '').toString(),
          (x['patente'] ?? '').toString(),
          (x['lavado_numero'] ?? '').toString(),
          (x['vehiculo'] ?? '').toString(),
          (x['servicio'] ?? '').toString(),
        ].join(' ').toLowerCase();
        return s.contains(q);
      }).toList();
    }
    _recomputeKPIs();
    setState(() {});
  }

  void _recomputeKPIs() {
    kLavados = _items.length;
    kIngresos = 0;
    kEfec = 0;
    kTransf = 0;

    int esperaTot = 0, lavadoTot = 0, esperaCount = 0, lavadoCount = 0;

    for (final d in _items) {
      final x = d.data();
      final pago = (x['pago'] ?? {}) as Map<String, dynamic>;
      final tipo = (pago['tipo'] ?? '') as String?;
      final valorLavado = _valorOrden(x);
      final montoPago = (pago['monto'] as num?)?.toDouble() ?? 0.0;
      kIngresos += valorLavado;
      if (tipo == 'efectivo') kEfec += montoPago;
      if (tipo == 'transferencia') kTransf += montoPago;

      final created = _toDate(x['created_at']);
      final started = _toDate(x['started_at']);
      final finished = _toDate(x['finished_at']);

      if (created != null && started != null) {
        esperaTot += started.difference(created).inMinutes;
        esperaCount++;
      }
      if (started != null && finished != null) {
        lavadoTot += finished.difference(started).inMinutes;
        lavadoCount++;
      }
    }

    kEsperaProm = esperaCount == 0
        ? Duration.zero
        : Duration(minutes: (esperaTot / esperaCount).round());
    kLavadoProm = lavadoCount == 0
        ? Duration.zero
        : Duration(minutes: (lavadoTot / lavadoCount).round());
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  double _valorOrden(Map<String, dynamic> data) {
    final pago = data['pago'];
    final pagoMonto = pago is Map ? (pago['monto'] as num?)?.toDouble() : null;
    return (data['precio_snapshot'] as num?)?.toDouble() ??
        (data['precio'] as num?)?.toDouble() ??
        pagoMonto ??
        0.0;
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          titleTextStyle: const TextStyle(
              color: kPrimary, fontSize: 20, fontWeight: FontWeight.w600),
          iconTheme: const IconThemeData(color: kPrimary),
          title: const Text('Resumen de lavados'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _panelMaxW),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(_radius)),
                        child: const Row(
                          children: [
                            Icon(Icons.list_alt, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Lavados',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    SliverToBoxAdapter(child: _filtrosCard()),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    SliverToBoxAdapter(child: _kpisGrid()),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (_loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('Sin resultados')),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            if (i.isOdd) return const SizedBox(height: 8);
                            return _rowCard(_items[i ~/ 2]);
                          },
                          childCount: _items.length * 2 - 1,
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Widgets =====
  Widget _filtrosCard() {
    final desdeStr = DateFormat('dd/MM/yyyy').format(_range.start);
    final hastaStr = DateFormat('dd/MM/yyyy')
        .format(_range.end.subtract(const Duration(days: 1)));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          // Rango de fechas
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 560;
            final desde = OutlinedButton.icon(
              onPressed: _pickDesde,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text('Desde  $desdeStr', overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kPrimary),
                foregroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            );
            final hasta = OutlinedButton.icon(
              onPressed: _pickHasta,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text('Hasta  $hastaStr', overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kPrimary),
                foregroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            );

            if (!narrow) {
              return Row(children: [
                Expanded(child: desde),
                const SizedBox(width: 8),
                Expanded(child: hasta),
              ]);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                desde,
                const SizedBox(height: 8),
                hasta,
              ],
            );
          }),
          const SizedBox(height: 12),
          // Línea de filtros
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: _serviciosCol.orderBy('nombre').get(),
            builder: (_, s) {
              final servicios = <String>['todos'];
              if (s.hasData) {
                for (final d in s.data!.docs) {
                  if ((d.data()['activo'] as bool?) ?? true) {
                    servicios.add((d.data()['nombre'] ?? '').toString());
                  }
                }
              }
              return LayoutBuilder(builder: (_, c) {
                final wide = c.maxWidth > 720;
                final pagoField = DropdownButtonFormField<String>(
                  initialValue: _pago,
                  items: const [
                    DropdownMenuItem(
                        value: 'todos', child: Text('Todos los pagos')),
                    DropdownMenuItem(
                        value: 'efectivo', child: Text('Solo efectivo')),
                    DropdownMenuItem(
                        value: 'transferencia',
                        child: Text('Solo transferencia')),
                    DropdownMenuItem(value: 'otro', child: Text('Solo otro')),
                  ],
                  onChanged: (v) => setState(() => _pago = v ?? 'todos'),
                  decoration: const InputDecoration(
                      labelText: 'Medio de pago', border: OutlineInputBorder()),
                );
                final servicioField = DropdownButtonFormField<String>(
                  initialValue: _servicio,
                  items: servicios
                      .map((e) => DropdownMenuItem(
                          value: e,
                          child:
                              Text(e == 'todos' ? 'Todos los servicios' : e)))
                      .toList(),
                  onChanged: (v) => setState(() => _servicio = v ?? 'todos'),
                  decoration: const InputDecoration(
                      labelText: 'Servicio', border: OutlineInputBorder()),
                );
                final buscarField = TextField(
                  controller: _buscaCtrl,
                  onChanged: (_) => _aplicarBusqueda(),
                  decoration: const InputDecoration(
                    labelText:
                        'Buscar (cliente / tel / patente / vehículo / servicio)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                );
                final aplicarButton = SizedBox(
                  width: wide ? 140 : double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _cargar(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Aplicar'),
                  ),
                );

                if (wide) {
                  return Row(children: [
                    Expanded(child: pagoField),
                    const SizedBox(width: 8),
                    Expanded(child: servicioField),
                    const SizedBox(width: 8),
                    Expanded(child: buscarField),
                    const SizedBox(width: 8),
                    aplicarButton,
                  ]);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pagoField,
                    const SizedBox(height: 8),
                    servicioField,
                    const SizedBox(height: 8),
                    buscarField,
                    const SizedBox(height: 8),
                    aplicarButton,
                  ],
                );
              });
            },
          ),
        ],
      ),
    );
  }

  // KPIs responsive en grilla
  Widget _kpisGrid() {
    String dFmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    Widget card(String label, String value, IconData icon) {
      return Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: kPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = <Widget>[
      card('Lavados', '$kLavados', Icons.local_car_wash),
      card('Valor lavados', _money.format(kIngresos), Icons.payments),
      card('Efectivo', _money.format(kEfec), Icons.attach_money),
      card('Transferencia', _money.format(kTransf), Icons.swap_horiz),
      card('Espera prom.', dFmt(kEsperaProm), Icons.hourglass_bottom),
      card('Lavado prom.', dFmt(kLavadoProm), Icons.timer),
    ];

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      int cols;
      if (w < 420) {
        cols = 1;
      } else if (w < 740) {
        cols = 2;
      } else if (w < 980) {
        cols = 3;
      } else {
        cols = 3;
      }

      return GridView.count(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3.4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: items,
      );
    });
  }

  Widget _rowCard(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data();
    final cli = (x['cliente_snapshot'] ?? {}) as Map<String, dynamic>;
    final nombre = (cli['nombre'] ?? '').toString();
    final apellido = (cli['apellido'] ?? '').toString();
    final nombreCompleto = [nombre, apellido]
            .where((e) => e.trim().isNotEmpty)
            .join(' ')
            .trim()
            .isEmpty
        ? (cli['nombre_completo'] ?? '').toString()
        : '$nombre $apellido';
    final tel = (cli['telefono'] ?? '').toString();
    final veh = (x['vehiculo'] ?? '').toString();
    final patente = (x['patente'] ?? '').toString();
    final srv = (x['servicio'] ?? '').toString();
    final lavadoNumero = (x['lavado_numero'] as num?)?.toInt();

    final pago = (x['pago'] ?? {}) as Map<String, dynamic>;
    final tipo = (pago['tipo'] ?? '').toString();
    final monto = _valorOrden(x);

    final started = _toDate(x['started_at']);
    final finished = _toDate(x['finished_at']);
    final created = _toDate(x['created_at']);

    final espera = (created != null && started != null)
        ? started.difference(created)
        : null;
    final dur = (started != null && finished != null)
        ? finished.difference(started)
        : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetalle(d),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6EEF9)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patente.trim().isEmpty
                            ? '$nombreCompleto • $veh'
                            : '$nombreCompleto • $patente • $veh',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.access_time, size: 14, color: kPrimary),
                        const SizedBox(width: 4),
                        Text(
                          finished == null
                              ? '-'
                              : DateFormat('dd/MM HH:mm').format(finished),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.local_car_wash, size: 14, color: kPrimary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(srv,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87)),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.phone, size: 14, color: Colors.black45),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(tel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Text('Espera: ',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
                        Text(_fmtDur(espera),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 12),
                        const Text('Lavado: ',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
                        Text(_fmtDur(dur),
                            style: const TextStyle(fontSize: 12)),
                      ]),
                    ]),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _lavadoNumeroChip(lavadoNumero),
                  const SizedBox(height: 4),
                  Text(_money.format(monto),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  _chip(tipo.isEmpty ? '—' : tipo),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDur(Duration? d) {
    if (d == null) return '—';
    final m = d.inMinutes;
    final h = m ~/ 60;
    final mm = m % 60;
    return h > 0 ? '${h}h ${mm}m' : '${mm}m';
  }

  Widget _chip(String t) {
    final c = t == 'efectivo'
        ? const Color(0xFF10B981)
        : t == 'transferencia'
            ? const Color(0xFF3B82F6)
            : t == 'otro'
                ? const Color(0xFF8B5CF6)
                : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.10),
        border: Border.all(color: c.withOpacity(.25)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(t,
          style:
              TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _lavadoNumeroChip(int? n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: .08),
        border: Border.all(color: kPrimary.withValues(alpha: .20)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        n == null ? '#-' : '#$n',
        style: const TextStyle(
          fontSize: 12,
          color: kPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _pickDesde() async {
    final hastaVisible = _range.end.subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _range.start,
      firstDate: DateTime(2023),
      lastDate: hastaVisible,
    );
    if (picked != null) {
      setState(() {
        _range = DateTimeRange(start: picked, end: _range.end);
      });
      _cargar();
    }
  }

  Future<void> _pickHasta() async {
    final hastaVisible = _range.end.subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: hastaVisible,
      firstDate: _range.start,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _range = DateTimeRange(
          start: _range.start,
          end: DateTime(picked.year, picked.month, picked.day)
              .add(const Duration(days: 1)),
        );
      });
      _cargar();
    }
  }

  // ===== Detalle + Editar =====
  void _showDetalle(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data();
    final cli = (x['cliente_snapshot'] ?? {}) as Map<String, dynamic>;
    final pago = (x['pago'] ?? {}) as Map<String, dynamic>;
    final lavadoNumero = (x['lavado_numero'] as num?)?.toInt();

    final nombre = (cli['nombre'] ?? '').toString();
    final apellido = (cli['apellido'] ?? '').toString();
    final nombreCompleto = [nombre, apellido]
            .where((e) => e.trim().isNotEmpty)
            .join(' ')
            .trim()
            .isEmpty
        ? (cli['nombre_completo'] ?? '').toString()
        : '$nombre $apellido';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(nombreCompleto.isEmpty ? 'Detalle' : nombreCompleto),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dl('Nro. lavado', lavadoNumero == null ? '-' : '#$lavadoNumero'),
              _dl('Teléfono', (cli['telefono'] ?? '—').toString()),
              _dl('Vehículo', (x['vehiculo'] ?? '—').toString()),
              _dl('Patente', (x['patente'] ?? '—').toString()),
              _dl('Servicio', (x['servicio'] ?? '—').toString()),
              _dl('Monto', _money.format(_valorOrden(x))),
              _dl('Medio de pago', (pago['tipo'] ?? '—').toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () async {
              // cerrar el diálogo con el rootNavigator
              Navigator.of(context, rootNavigator: true).pop();
              // abrir la hoja en el próximo micro-tick con el context del State
              Future.microtask(() => _openEditSheet(d));
            },
            child: const Text('Editar'),
          ),
        ],
      ),
    );
  }

  // ====== Sheet de edición (sin fechas) ======
  final _vehCtrl = TextEditingController();
  final _patCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _tipoPago = 'efectivo';
  String? _srvSelId;
  String? _srvSelNombre;
  double? _srvPrecio;

  String _normPat(String s) => normalizarPatente(s);

  Future<void> _openEditSheet(
      QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final x = d.data();
    final pago = (x['pago'] ?? {}) as Map<String, dynamic>;

    _vehCtrl.text = (x['vehiculo'] ?? '').toString();
    _patCtrl.text = (x['patente'] ?? '').toString();
    _montoCtrl.text =
        ((pago['monto'] as num?) ?? (x['precio_snapshot'] as num?) ?? 0)
            .toStringAsFixed(0);
    _tipoPago = (pago['tipo'] ?? 'efectivo').toString();
    _srvSelNombre = (x['servicio'] ?? '').toString();
    _srvSelId = (x['servicio_id'] ?? '').toString();
    _srvPrecio = (x['precio_snapshot'] as num?)?.toDouble();

    QuerySnapshot<Map<String, dynamic>> servicios;
    try {
      servicios = await _serviciosCol.orderBy('nombre').get();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar servicios: $e')),
      );
      return;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setS) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Editar orden',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Vehículo', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _patCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r"[A-Za-z0-9 \-]")),
                      LengthLimitingTextInputFormatter(12),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Patente / matricula',
                      hintText: patenteHint,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (s) {
                      final up = s.toUpperCase();
                      if (s != up) {
                        final sel = _patCtrl.selection;
                        _patCtrl.value =
                            TextEditingValue(text: up, selection: sel);
                      }
                      setS(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _tipoPago,
                    items: const [
                      DropdownMenuItem(
                          value: 'efectivo', child: Text('Efectivo')),
                      DropdownMenuItem(
                          value: 'transferencia', child: Text('Transferencia')),
                      DropdownMenuItem(value: 'otro', child: Text('Otro')),
                    ],
                    onChanged: (v) => setS(() => _tipoPago = v ?? 'efectivo'),
                    decoration: const InputDecoration(
                        labelText: 'Medio de pago',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _montoCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Monto',
                        prefixText: r'$ ',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _srvSelId?.isEmpty == true ? null : _srvSelId,
                    items: servicios.docs
                        .where((e) => (e.data()['activo'] as bool?) ?? true)
                        .map((e) => DropdownMenuItem(
                              value: e.id,
                              child:
                                  Text((e.data()['nombre'] ?? '').toString()),
                            ))
                        .toList(),
                    onChanged: (id) {
                      final e = servicios.docs.firstWhere((z) => z.id == id);
                      final data = e.data();
                      setS(() {
                        _srvSelId = e.id;
                        _srvSelNombre = (data['nombre'] ?? '').toString();
                        _srvPrecio = (data['precio'] as num?)?.toDouble();
                      });
                    },
                    decoration: const InputDecoration(
                        labelText: 'Servicio', border: OutlineInputBorder()),
                  ),
                  if (_srvPrecio != null) ...[
                    const SizedBox(height: 6),
                    Text('Precio de servicio: ${_money.format(_srvPrecio)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            // Validaciones
                            final m = double.tryParse(_montoCtrl.text.trim());
                            if (m == null || m <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Monto inválido')));
                              return;
                            }
                            final p = _normPat(_patCtrl.text.trim());
                            if (!(p.isEmpty || patenteValida(p))) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text(patenteError)),
                              );
                              return;
                            }

                            final cambios = <String, dynamic>{
                              'vehiculo': _vehCtrl.text.trim(),
                              if (_patCtrl.text.trim().isEmpty) ...{
                                'patente': FieldValue.delete(),
                                'patente_norm': FieldValue.delete(),
                              } else ...{
                                'patente': _patCtrl.text.trim().toUpperCase(),
                                'patente_norm': p,
                              },
                              'pago': {'tipo': _tipoPago, 'monto': m},
                              if (_srvSelNombre != null &&
                                  _srvSelNombre!.isNotEmpty) ...{
                                'servicio': _srvSelNombre,
                                'servicio_id': _srvSelId,
                                if (_srvPrecio != null)
                                  'precio_snapshot': _srvPrecio,
                              },
                              // Campos de auditoría (válidos aquí)
                              'edited_at': FieldValue.serverTimestamp(),
                              'edited_by_uid': _uid,
                              'edited_by_role': 'admin',
                            };

                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);

                            try {
                              // 1) actualizar campos
                              await d.reference.update(cambios);

                              // 2) agregar log sin serverTimestamp dentro de arrayUnion
                              await d.reference.update({
                                'edit_log': FieldValue.arrayUnion([
                                  {
                                    'at': Timestamp
                                        .now(), // ✅ válido dentro de arrayUnion
                                    'by': _uid,
                                    'changes': {
                                      'vehiculo': _vehCtrl.text.trim(),
                                      'patente':
                                          _patCtrl.text.trim().toUpperCase(),
                                      'pago.tipo': _tipoPago,
                                      'pago.monto': m,
                                      'servicio': _srvSelNombre,
                                    }
                                  }
                                ])
                              });

                              if (!mounted) return;
                              navigator.pop();
                              _cargar();
                              messenger.showSnackBar(const SnackBar(
                                  content: Text('Orden actualizada')));
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                    content: Text('No se pudo actualizar: $e')),
                              );
                            }
                          },
                          child: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dl(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
            width: 130,
            child:
                Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(v)),
      ]),
    );
  }
}

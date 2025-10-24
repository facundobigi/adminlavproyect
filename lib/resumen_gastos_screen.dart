// resumen_gastos_screen.dart
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ResumenGastosScreen extends StatefulWidget {
  final DateTimeRange? initialRange;
  const ResumenGastosScreen({super.key, this.initialRange});

  @override
  State<ResumenGastosScreen> createState() => _ResumenGastosScreenState();
}

class _ResumenGastosScreenState extends State<ResumenGastosScreen> {
  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 22, 53, 117);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 720; // un poco mÃ¡s ancho en desktop
  static const double _radius = 16;

  // NÃºmeros tabulares
  static const _numStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  late DateTimeRange _rango;
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    _rango = widget.initialRange ??
        DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Formatos seguros para web
  String _fmtFecha(DateTime d) {
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(d);
    } catch (_) {
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mi = d.minute.toString().padLeft(2, '0');
      return '$dd/$mm/${d.year} $hh:$mi';
    }
  }

  String _fmtMoney(num v) {
    try {
      return NumberFormat.currency(locale: 'es_AR', symbol: r'$').format(v);
    } catch (_) {
      return '\$ ${v.toStringAsFixed(0)}';
    }
  }

  Future<void> _pickRange() async {
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _rango,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kPrimary,
            onPrimary: Colors.white,
            onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (res != null) setState(() => _rango = res);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('gastos')
        .where('fecha', isGreaterThanOrEqualTo: _rango.start)
        .where('fecha', isLessThan: _rango.end)
        .orderBy('fecha', descending: true);

    final rangoLabel =
        '${DateFormat('dd/MM/yy').format(_rango.start)}  al  ${DateFormat('dd/MM/yy').format(_rango.end.subtract(const Duration(days: 1)))}';

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
          title: const Text('Resumen de gastos'),
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
                          Icon(Icons.receipt_long, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Gastos',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Filtro rango
                    Container(
                      padding: const EdgeInsets.all(12),
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
                      child: LayoutBuilder(
                        builder: (_, c) {
                          final wide = c.maxWidth >= 560;
                          final btn = OutlinedButton.icon(
                            onPressed: _pickRange,
                            icon: const Icon(Icons.date_range, size: 18),
                            label: Text('Rango  $rangoLabel'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kPrimary),
                              foregroundColor: kPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                            ),
                          );
                          return wide
                              ? Row(
                                  children: [
                                    Expanded(child: btn),
                                    const SizedBox(width: 12),
                                    const _HintText(
                                      text:
                                          'ElegÃ­ un rango para ver el detalle y el total.',
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    btn,
                                    const SizedBox(height: 8),
                                    const _HintText(
                                      text:
                                          'ElegÃ­ un rango para ver el detalle y el total.',
                                      alignCenter: true,
                                    ),
                                  ],
                                );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // BÃºsqueda por nombre
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_radius),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) =>
                            setState(() => _search = v.trim().toLowerCase()),
                        decoration: const InputDecoration(
                          hintText: 'Buscar gasto por nombre',
                          prefixIcon: Icon(Icons.search),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Lista + total (reactivo)
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: q.snapshots(),
                        builder: (_, s) {
                          if (s.hasError) {
                            return Center(
                              child: Text(
                                'Error: ${s.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          }
                          if (!s.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final allDocs = s.data!.docs;
                          final docs = _search.isEmpty
                              ? allDocs
                              : allDocs.where((d) {
                                  final x = d.data();
                                  final desc = (x['descripcion'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  return desc.contains(_search);
                                }).toList();
                          final total = docs.fold<double>(
                            0,
                            (a, d) =>
                                a +
                                ((d.data()['monto'] as num?)?.toDouble() ?? 0),
                          );

                          if (docs.isEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _TotalCard(total: total, fmt: _fmtMoney),
                                const Expanded(
                                  child: Center(
                                      child: Text('Sin gastos en el rango.')),
                                ),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              _TotalCard(total: total, fmt: _fmtMoney),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(_radius),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x11000000),
                                        blurRadius: 10,
                                        offset: Offset(0, 3),
                                      )
                                    ],
                                  ),
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: docs.length,
                                    separatorBuilder: (_, __) => const Divider(
                                        height: 1, color: Color(0xFFEAECEF)),
                                    itemBuilder: (_, i) {
                                      final x = docs[i].data();
                                      final monto =
                                          (x['monto'] as num?)?.toDouble() ?? 0;
                                      final ts = x['fecha'];
                                      final fecha = ts is Timestamp
                                          ? ts.toDate()
                                          : DateTime.now();
                                      final desc =
                                          (x['descripcion'] ?? '').toString();
                                      final metodo =
                                          (x['metodo_pago'] as String?) ??
                                              'efectivo';
                                      final tipo = (x['tipo_gasto']
                                              as String?) ??
                                          ((x['afecta_resumen_diario'] == false)
                                              ? 'general'
                                              : 'diario');
                                      final metodoLabel =
                                          metodo == 'transferencia'
                                              ? 'Transferencia'
                                              : 'Efectivo';
                                      final tipoLabel = tipo == 'general'
                                          ? 'General'
                                          : 'Diario';

                                      return ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                        title: Text(
                                          desc.isEmpty
                                              ? '(sin descripciÃ³n)'
                                              : desc,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w500),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(_fmtFecha(fecha)),
                                            Text(
                                              'Pago: $metodoLabel | Tipo: $tipoLabel',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Text(_fmtMoney(monto),
                                            style: _numStyle),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
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

class _TotalCard extends StatelessWidget {
  final double total;
  final String Function(num) fmt;
  const _TotalCard({required this.total, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Total gastos', style: TextStyle(fontSize: 16)),
          ),
          Text(
            fmt(total),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;
  final bool alignCenter;
  const _HintText({required this.text, this.alignCenter = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignCenter ? TextAlign.center : TextAlign.start,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    );
  }
}

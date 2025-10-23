// balance_screen.dart
import 'dart:ui' show FontFeature;
import 'dart:convert';
import 'dart:html' as html; // Export CSV en Web

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'resumen_gastos_screen.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});
  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  late final DocumentReference _userRef =
      FirebaseFirestore.instance.collection('users').doc(_uid);

  // Paleta y tokens
  static const Color kPrimary = Color.fromARGB(255, 19, 50, 112);
  static const Color kGreen = Color(0xFF1E9E6A);
  static const Color kRed = Color(0xFFC62828);
  static const Color kBg = Color(0xFFF7F8FA);
  static const double _panelMaxW = 720;
  static const double _radius = 16;

  // Estilo numérico
  static const _numStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$');
  String fmt(num v) {
    try {
      final s = _money.format(v.abs());
      return v < 0 ? '-$s' : s;
    } catch (_) {
      final s = '\$ ${v.abs().toStringAsFixed(2)}';
      return v < 0 ? '-$s' : s;
    }
  }

  String fmtDate(DateTime? d) {
    if (d == null) return '...';
    try {
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
  }

  DateTime? fechaDesde;
  DateTime? fechaHasta;

  int totalLavados = 0;
  double totalEfectivo = 0;
  double totalTransferencia = 0;
  double totalOtro = 0;
  double totalIngresos = 0;
  double totalGastos = 0;
  double totalLavadores = 0;
  double cierreNeto = 0;
  double cierreEfectivo = 0;

  double _porcLav = 0.40;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    fechaDesde = ahora.subtract(const Duration(days: 7));
    fechaHasta = ahora;
    _cargarPorcentaje().then((_) => cargarBalance());
  }

  Future<void> _cargarPorcentaje() async {
    final d = await _userRef.collection('config').doc('app').get();
    final p = (d.data()?['porcentaje_lavadores'] as num?)?.toDouble();
    if (p != null && p > 0 && p < 1) _porcLav = p;
  }

  Future<void> cargarBalance() async {
    if (fechaDesde == null || fechaHasta == null) return;
    final inicio = DateTime(fechaDesde!.year, fechaDesde!.month, fechaDesde!.day);
    final fin = DateTime(fechaHasta!.year, fechaHasta!.month, fechaHasta!.day + 1);

    final qs = await _userRef
        .collection('ordenes')
        .where('delivered_at', isGreaterThanOrEqualTo: inicio)
        .where('delivered_at', isLessThan: fin)
        .get();

    double efectivo = 0, transferencia = 0, otro = 0;
    for (final d in qs.docs) {
      final data = d.data();
      final pago = data['pago'];
      if (pago is Map) {
        final monto = (pago['monto'] as num?)?.toDouble() ?? 0.0;
        final tipo = (pago['tipo'] ?? '') as String? ?? '';
        if (tipo == 'efectivo') efectivo += monto;
        else if (tipo == 'transferencia') transferencia += monto;
        else if (tipo == 'otro') otro += monto;
        else efectivo += monto; // fallback histórico
      } else {
        efectivo += (data['precio'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final gastos = await _userRef
        .collection('gastos')
        .where('fecha', isGreaterThanOrEqualTo: inicio)
        .where('fecha', isLessThan: fin)
        .get();
    final gast = gastos.docs.fold<double>(0, (s, d) => s + (((d.data() as Map)['monto'] as num?)?.toDouble() ?? 0.0));

    final ingresos = efectivo + transferencia + otro;
    final pagoLav = ingresos * _porcLav;
    final cierre = ingresos - gast - pagoLav;
    final cierreCash = efectivo - gast - pagoLav;

    if (!mounted) return;
    setState(() {
      totalLavados = qs.size;
      totalEfectivo = efectivo;
      totalTransferencia = transferencia;
      totalOtro = otro;
      totalIngresos = ingresos;
      totalGastos = gast;
      totalLavadores = pagoLav;
      cierreNeto = cierre;
      cierreEfectivo = cierreCash;
    });
  }

  Future<void> _pickDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaDesde ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: fechaHasta ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() => fechaDesde = picked);
      cargarBalance();
    }
  }

  Future<void> _pickHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaHasta ?? DateTime.now(),
      firstDate: fechaDesde ?? DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => fechaHasta = picked);
      cargarBalance();
    }
  }

  // ===== Exportación CSV solo con el card =====
  Future<void> _exportarCSV() async {
    final inicio = fechaDesde;
    final fin = fechaHasta;
    if (inicio == null || fin == null) return;

    final csv = StringBuffer();
    csv.writeln('Rango,${DateFormat('dd/MM/yyyy').format(inicio)},${DateFormat('dd/MM/yyyy').format(fin)}');
    csv.writeln('Concepto,Valor');
    csv.writeln('Lavados,$totalLavados');
    csv.writeln('Efectivo,${totalEfectivo.toStringAsFixed(2)}');
    csv.writeln('Transferencia,${totalTransferencia.toStringAsFixed(2)}');
    csv.writeln('Otro,${totalOtro.toStringAsFixed(2)}');
    csv.writeln('Ingresos totales,${totalIngresos.toStringAsFixed(2)}');
    csv.writeln('Gastos,${totalGastos.toStringAsFixed(2)}');
    csv.writeln('Pago a lavadores ${(_porcLav * 100).toStringAsFixed(0)}%,${totalLavadores.toStringAsFixed(2)}');
    csv.writeln('Cierre efectivo,${cierreEfectivo.toStringAsFixed(2)}');
    csv.writeln('Cierre neto,${cierreNeto.toStringAsFixed(2)}');

    final bytes = utf8.encode(csv.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: url)
      ..download =
          'balance_${DateFormat('yyyyMMdd').format(inicio)}_${DateFormat('yyyyMMdd').format(fin)}.csv';
    html.document.body!.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final desdeStr = fmtDate(fechaDesde);
    final hastaStr = fmtDate(fechaHasta);

    final scaler =
        MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);

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
          title: const Text('Balance'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Exportar CSV',
              onPressed: _exportarCSV,
              icon: const Icon(Icons.file_download),
              color: kPrimary,
            ),
          ],
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
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.insights, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Balance',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Filtros y export
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_radius),
                        boxShadow: const [
                          BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (_, c) {
                          final narrow = c.maxWidth < 560;
                          final children = [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickDesde,
                                icon: const Icon(Icons.calendar_month, size: 18),
                                label: Text('Desde  $desdeStr', overflow: TextOverflow.ellipsis),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: kPrimary),
                                  foregroundColor: kPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickHasta,
                                icon: const Icon(Icons.calendar_month, size: 18),
                                label: Text('Hasta  $hastaStr', overflow: TextOverflow.ellipsis),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: kPrimary),
                                  foregroundColor: kPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 160,
                              child: ElevatedButton.icon(
                                onPressed: _exportarCSV,
                                icon: const Icon(Icons.file_download),
                                label: const Text('Exportar CSV'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ];

                          if (!narrow) return Row(children: children);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              children[0],
                              const SizedBox(height: 8),
                              children[2],
                              const SizedBox(height: 8),
                              children[4],
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Card resumen
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_radius),
                        boxShadow: const [
                          BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))
                        ],
                      ),
                      child: Column(
                        children: [
                          _row('Lavados', Text('$totalLavados', style: _numStyle)),
                          _row('Efectivo', Text(fmt(totalEfectivo), style: _numStyle)),
                          _row('Transferencia', Text(fmt(totalTransferencia), style: _numStyle)),
                          _row('Otros', Text(fmt(totalOtro), style: _numStyle)),
                          _row(
                            'Ingresos totales',
                            Text(fmt(totalIngresos), style: _numStyle.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 24, color: Color(0xFFEAECEF)),

                          // "resumen" a la derecha del total de gastos
                          Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    children: [
      const Text('Gastos', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      TextButton.icon(
        onPressed: () {
          final inicio = DateTime(fechaDesde!.year, fechaDesde!.month, fechaDesde!.day);
          final fin = DateTime(fechaHasta!.year, fechaHasta!.month, fechaHasta!.day + 1);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResumenGastosScreen(
                initialRange: DateTimeRange(start: inicio, end: fin),
              ),
            ),
          );
        },
        icon: const Icon(Icons.receipt_long, size: 18),
        label: const Text('resumen', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(foregroundColor: kPrimary),
      ),
      const Spacer(),
      DefaultTextStyle.merge(
        style: _numStyle,
        child: Text(fmt(totalGastos)),
      ),
    ],
  ),
),

                          _row(
                            'Pago a lavadores (${(_porcLav * 100).toStringAsFixed(0)}%)',
                            Text(fmt(totalLavadores), style: _numStyle),
                          ),
                          _row(
                            'Cierre efectivo',
                            Text(
                              fmt(cierreEfectivo),
                              style: _numStyle.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _cierreCinta(cierreNeto),
                        ],
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

  Widget _row(String l, Widget r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(l, style: const TextStyle(fontSize: 16))),
          DefaultTextStyle.merge(style: _numStyle, child: r),
        ],
      ),
    );
  }

  Widget _cierreCinta(double cierre) {
    final ok = cierre >= 0;
    final color = ok ? kGreen : kRed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ok ? Icons.trending_up : Icons.trending_down, color: color),
          const SizedBox(width: 8),
          Text('CIERRE NETO: ${fmt(cierre)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}







// home_screen.dart
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'registrogasto.dart';
import 'balance_screen.dart';
import 'checkin_screen.dart';
import 'cola_screen.dart';
import 'servicios_screen.dart';
import 'resumen_gastos_screen.dart';
import 'resumen_lavados_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  late final DocumentReference<Map<String, dynamic>> _userRef =
      FirebaseFirestore.instance.collection('users').doc(_uid);

  DateTime today = DateTime.now();

  int totalLavados = 0;
  double totalEfectivo = 0;
  double totalTransferencia = 0;
  double ingresosTotales = 0;
  double totalGastos = 0;
  double cierreEfectivo = 0;
  double pagoLavadores = 0;

  bool cargando = true;

  int enColaCount = 0, enLavCount = 0, listosCount = 0;

  double porcLav = 0.40;

  final NumberFormat _money = NumberFormat.currency(locale: 'es_AR', symbol: '\$');
  String fmt(num v) {
    final s = _money.format(v.abs());
    return v < 0 ? '-$s' : s;
  }

  // Paleta
  static const Color kPrimary = Color.fromARGB(255, 21, 54, 119);
  static const Color kPrimarySoft = Color(0xFFE6EEF9);
  static const Color kGreen = Color(0xFF1E9E6A);
  static const Color kRed = Color(0xFFC62828);
  static const Color kBg = Color(0xFFF7F8FA);

  // Números monoespaciados para alinear montos
  static const _numStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Layout tokens
  static const double _sideW = 320;         // ancho sidebar
  static const double _panelMaxW = 640;     // ancho máximo panel para alinear
  static const double _radius = 16;

  @override
  void initState() {
    super.initState();
    _cargarConfig().then((_) => cargarResumenDelDia());
  }

  Future<void> _cargarConfig() async {
    final d = await _userRef.collection('config').doc('app').get();
    final p = (d.data()?['porcentaje_lavadores'] as num?)?.toDouble();
    if (p != null && p > 0 && p < 1) porcLav = p;
  }

  Future<void> cargarResumenDelDia() async {
    setState(() => cargando = true);

    final inicioDia = DateTime(today.year, today.month, today.day);
    final finDia = inicioDia.add(const Duration(days: 1));

    final qs = await _userRef
        .collection('ordenes')
        .where('delivered_at', isGreaterThanOrEqualTo: inicioDia)
        .where('delivered_at', isLessThan: finDia)
        .get();

    double efectivo = 0, transferencia = 0;
    for (final d in qs.docs) {
      final data = d.data();
      final pagoRaw = data['pago'];
      if (pagoRaw is Map) {
        final pago = Map<String, dynamic>.from(pagoRaw);
        final monto = (pago['monto'] as num?)?.toDouble() ?? 0.0;
        final tipo = (pago['tipo'] as String?) ?? '';
        if (tipo == 'efectivo') {
          efectivo += monto;
        } else if (tipo == 'transferencia') {
          transferencia += monto;
        }
      } else {
        efectivo += (data['precio'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final gastos = await _userRef
        .collection('gastos')
        .where('fecha', isGreaterThanOrEqualTo: inicioDia)
        .where('fecha', isLessThan: finDia)
        .get();
    final gast = gastos.docs.fold<double>(
      0,
      (s, d) => s + ((d.data()['monto'] as num?)?.toDouble() ?? 0.0),
    );

    final enCola = await _userRef.collection('ordenes').where('estado', isEqualTo: 'en_cola').get();
    final enLav = await _userRef.collection('ordenes').where('estado', isEqualTo: 'en_lavado').get();
    final listos = await _userRef.collection('ordenes').where('estado', isEqualTo: 'listo').get();

    setState(() {
      totalLavados = qs.size;
      totalEfectivo = efectivo;
      totalTransferencia = transferencia;
      ingresosTotales = efectivo + transferencia;
      totalGastos = gast;
      pagoLavadores = ingresosTotales * porcLav;
      cierreEfectivo = ingresosTotales - totalGastos - pagoLavadores;

      enColaCount = enCola.size;
      enLavCount = enLav.size;
      listosCount = listos.size;

      cargando = false;
    });
  }

  Future<void> _editarPorcLav() async {
    final ctrl = TextEditingController(text: (porcLav * 100).toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Porcentaje lavadores'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: '%', hintText: '0–100'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true) {
      final n = int.tryParse(ctrl.text.trim()) ?? -1;
      if (n >= 0 && n <= 100) {
        final p = n / 100.0;
        await _userRef.collection('config').doc('app').set({
          'porcentaje_lavadores': p,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        setState(() {
          porcLav = p;
          pagoLavadores = ingresosTotales * porcLav;
          cierreEfectivo = ingresosTotales - totalGastos - pagoLavadores;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valor 0–100')));
        }
      }
    }
    ctrl.dispose();
  }

  void _go(Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    ).then((_) => cargarResumenDelDia());
  }

  @override
  Widget build(BuildContext context) {
    final fechaStr = DateFormat('dd/MM/yyyy').format(today);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(children: [
          SizedBox(height: 56, child: Image.asset('assets/admin.lav1.png')),
        ]),
        actions: [
          IconButton(
            tooltip: 'Salir',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 980;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1140),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: wide ? _wideLayout(fechaStr) : _narrowLayout(fechaStr),
                  ),
                ),
              );
            }),
    );
  }

  // ===== Layouts =====
  Widget _wideLayout(String fechaStr) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Izquierda: acciones (alineada por top con el panel)
        SizedBox(
          width: _sideW,
          child: Column(
            children: [
              _tilePrimary(Icons.person_add_alt_1, 'Check in', () => _go(const CheckInScreen())),
              const SizedBox(height: 12),
              _tilePrimary(Icons.playlist_add_check, 'Cola de trabajo', () => _go(const ColaScreen())),
              const SizedBox(height: 12),
              _tileAccent(Icons.receipt_long, 'Registrar Gasto', () => _go(const RegistroGastoScreen())),
              const SizedBox(height: 12),
              _tileSecondary(Icons.query_stats, 'Ver Balance', () => _go(const BalanceScreen())),
              const SizedBox(height: 12),
              _tileSecondary(Icons.settings, 'Gestionar servicios', () => _go(const ServiciosScreen())),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Derecha: panel con ancho fijo para alinear visualmente con el sidebar
        SizedBox(width: _panelMaxW, child: _panel(fechaStr)),
      ],
    );
  }

  Widget _narrowLayout(String fechaStr) {
    return Column(
      children: [
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: _panelMaxW), child: _panel(fechaStr)),
        const SizedBox(height: 24),
        _tilePrimary(Icons.person_add_alt_1, 'Check in', () => _go(const CheckInScreen())),
        const SizedBox(height: 12),
        _tilePrimary(Icons.playlist_add_check, 'Cola de trabajo', () => _go(const ColaScreen())),
        const SizedBox(height: 12),
        _tileAccent(Icons.receipt_long, 'Registrar Gasto', () => _go(const RegistroGastoScreen())),
        const SizedBox(height: 12),
        _tileSecondary(Icons.query_stats, 'Ver Balance', () => _go(const BalanceScreen())),
        const SizedBox(height: 12),
        _tileSecondary(Icons.settings, 'Gestionar servicios', () => _go(const ServiciosScreen())),
      ],
    );
  }

  // ===== Panel derecho =====
  Widget _panel(String fechaStr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header azul compacto (sin botón "Ayer")
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: const Color.fromARGB(255, 23, 56, 122), borderRadius: BorderRadius.circular(_radius)),
          child: Row(
            children: [
              _circleIcon(
                icon: Icons.chevron_left,
                onTap: () {
                  setState(() => today = today.subtract(const Duration(days: 1)));
                  cargarResumenDelDia();
                },
              ),
              const SizedBox(width: 8),
              const Text(
                'Resumen Diario',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: today,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => today = picked);
                    cargarResumenDelDia();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        transitionBuilder: (c, a) =>
                            FadeTransition(opacity: a, child: SlideTransition(position: a.drive(Tween(begin: const Offset(0, .1), end: Offset.zero)), child: c)),
                        child: Text(
                          fechaStr,
                          key: ValueKey(fechaStr),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _circleIcon(
                icon: Icons.chevron_right,
                onTap: () {
                  setState(() => today = today.add(const Duration(days: 1)));
                  cargarResumenDelDia();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card resumen
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Column(
            children: [
              Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    children: [
      const Text('Lavados', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 6),
      TextButton.icon(
        onPressed: () => _go(const ResumenLavadosScreen()),
        icon: const Icon(Icons.list_alt, size: 18),
        label: const Text('resumen', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: kPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      const Spacer(),
      DefaultTextStyle.merge(
        style: _numStyle,
        child: _animNum('$totalLavados'),
      ),
    ],
  ),
),
              _row('Efectivo', _animNum(fmt(totalEfectivo))),
              _row('Transferencia', _animNum(fmt(totalTransferencia))),
              _row('Total ingresos', _animNum(fmt(ingresosTotales), bold: true)),
              const SizedBox(height: 10),
              const Divider(height: 24, color: Color(0xFFEAECEF)),
              _rowWithAction(
                'Gastos',
                _animNum(fmt(totalGastos)),
                icon: Icons.receipt_long,
                label: 'resumen',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ResumenGastosScreen()))
                      .then((_) => cargarResumenDelDia());
                },
              ),
              _rowWithAction(
                'Pago a lavadores (${(porcLav * 100).round()}%)',
                _animNum(fmt(pagoLavadores)),
                icon: Icons.edit,
                label: 'editar',
                onPressed: _editarPorcLav,
              ),
              const SizedBox(height: 12),
              _cierreCinta(cierreEfectivo),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // KPIs
        Row(
          children: [
            Expanded(child: _kpiCard(Icons.hourglass_bottom, enColaCount, 'En cola', const Color(0xFFF59E0B), onTap: () => _go(const ColaScreen()))),
            const SizedBox(width: 8),
            Expanded(child: _kpiCard(Icons.local_car_wash, enLavCount, 'En lavado', const Color(0xFF3B82F6), onTap: () => _go(const ColaScreen()))),
            const SizedBox(width: 8),
            Expanded(child: _kpiCard(Icons.check_circle, listosCount, 'Listos', const Color(0xFF10B981), onTap: () => _go(const ColaScreen()))),
          ],
        ),
      ],
    );
  }

  // ===== Widgets base =====
  Widget _animNum(String text, {bool bold = false}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: Text(
        text,
        key: ValueKey(text),
        style: _numStyle.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w700),
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

  Widget _rowWithAction(String l, Widget r,
      {required IconData icon, required String label, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(l, style: const TextStyle(fontSize: 16))),
          DefaultTextStyle.merge(style: _numStyle, child: r),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: kPrimary),
          ),
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
          Text('CIERRE NETO: ${fmt(cierre)}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _kpiCard(IconData icon, int valor, String etiqueta, Color topBar, {VoidCallback? onTap}) {
    final child = Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: topBar,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, size: 20, color: kPrimary),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                  child: Text(
                    '$valor',
                    key: ValueKey(valor),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? child
        : InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: child);
  }

  Widget _tilePrimary(IconData icon, String label, VoidCallback onTap) {
    return _tileBase(icon: icon, label: label, onTap: onTap, bg: kPrimary, fg: Colors.white);
  }

  Widget _tileSecondary(IconData icon, String label, VoidCallback onTap) {
    return _tileBase(
      icon: icon,
      label: label,
      onTap: onTap,
      bg: Colors.white,
      fg: kPrimary,
      border: Border.all(color: kPrimarySoft, width: 1.4),
    );
  }

  Widget _tileAccent(IconData icon, String label, VoidCallback onTap) {
    return _tileBase(
      icon: icon,
      label: label,
      onTap: onTap,
      bg: Colors.white,
      fg: kRed,
      border: Border.all(color: kRed.withOpacity(.25), width: 1.4),
    );
  }

  Widget _tileBase({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color bg,
    required Color fg,
    Border? border,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_right, color: fg),
          ],
        ),
      ),
    );
  }

  Widget _circleIcon({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: Colors.white.withOpacity(.12), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}









import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../textos.dart';

const _colorEstacion = Color(0xFF0D47A1);
const _colorAtencion = Color(0xFF8D6E00);
const _colorAlerta = Color(0xFFBF4B00);
const _colorEvacuacion = Color(0xFFB71C1C);

/// "De 4,42 m a 5,95 m (subió 1,53 m). Máximo: 5,95 m el 9/10."
/// Sirve de resumen visible y de descripción del gráfico para el lector de pantalla.
String resumenHistorial(List<PuntoHistorial> puntos) {
  if (puntos.isEmpty) return 'No hay lecturas en este período.';
  final primero = puntos.first, ultimo = puntos.last;
  final maximo = puntos.reduce((a, b) => b.valorM > a.valorM ? b : a);
  final cambio = ultimo.valorM - primero.valorM;
  final movimiento = (cambio.abs() * 100).round() == 0
      ? 'sin cambios'
      : '${cambio > 0 ? 'subió' : 'bajó'} ${formatoAltura(cambio.abs())} m';
  return 'Del ${formatoDiaCorto(primero.fecha)} al ${formatoDiaCorto(ultimo.fecha)}: '
      'de ${formatoAltura(primero.valorM)} m a ${formatoAltura(ultimo.valorM)} m ($movimiento). '
      'Máximo: ${formatoAltura(maximo.valorM)} m el ${formatoDiaCorto(maximo.fecha)}.';
}

class PantallaGrafico extends StatefulWidget {
  final Datos? datos;

  /// Solo para pruebas: permite fijar la hora actual.
  final DateTime? ahora;

  const PantallaGrafico({super.key, required this.datos, this.ahora});

  @override
  State<PantallaGrafico> createState() => _PantallaGraficoState();
}

class _PantallaGraficoState extends State<PantallaGrafico> {
  int _dias = 7;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final historial = widget.datos?.historial ?? const <PuntoHistorial>[];
    final umbrales = widget.datos?.umbrales;
    final ahora = widget.ahora ?? DateTime.now();
    final desde = ahora.subtract(Duration(days: _dias));
    final puntos = historial.where((p) => p.fecha.isAfter(desde)).toList();
    final diasConDatos = historial.isEmpty ? 0 : ahora.difference(historial.first.fecha).inDays;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Altura del río en los últimos días', style: tema.titleLarge),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 días')),
            ButtonSegment(value: 30, label: Text('30 días')),
            ButtonSegment(value: 90, label: Text('90 días')),
          ],
          selected: {_dias},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _dias = s.first),
        ),
        const SizedBox(height: 12),
        Text(resumenHistorial(puntos), style: tema.bodyLarge),
        if (puntos.isNotEmpty && diasConDatos < _dias - 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Por ahora hay datos guardados desde el ${formatoDiaCorto(historial.first.fecha)}.',
              style: tema.bodyMedium,
            ),
          ),
        const SizedBox(height: 16),
        if (puntos.isNotEmpty)
          Semantics(
            label: 'Gráfico de la altura del río. ${resumenHistorial(puntos)}',
            excludeSemantics: true,
            child: SizedBox(height: 320, child: _Grafico(puntos: puntos, umbrales: umbrales, desde: desde, hasta: ahora)),
          ),
        const SizedBox(height: 16),
        _Leyenda(umbrales: umbrales, hayPrefectura: puntos.any((p) => p.fuente == 'prefectura')),
        const SizedBox(height: 12),
        Text('Fuente: CARU (estación automática y Prefectura). Alturas en metros.', style: tema.bodyMedium),
      ],
    );
  }
}

class _Grafico extends StatelessWidget {
  final List<PuntoHistorial> puntos;
  final Umbrales? umbrales;
  final DateTime desde;
  final DateTime hasta;

  const _Grafico({required this.puntos, required this.umbrales, required this.desde, required this.hasta});

  // El eje X va en horas contadas desde la medianoche (hora de Uruguay) del
  // primer día, para que las marcas del eje caigan justo en el cambio de día.
  DateTime get _origen {
    final d = enHoraUruguay(desde);
    return DateTime.utc(d.year, d.month, d.day).add(const Duration(hours: 3));
  }

  double _x(DateTime f) => f.difference(_origen).inMinutes / 60;
  DateTime _fechaDe(double x) => _origen.add(Duration(minutes: (x * 60).round()));

  @override
  Widget build(BuildContext context) {
    final estacion = [for (final p in puntos) if (p.fuente == 'estacion') FlSpot(_x(p.fecha), p.valorM)];
    final prefectura = [for (final p in puntos) if (p.fuente == 'prefectura') FlSpot(_x(p.fecha), p.valorM)];

    final lineas = <(double, Color, String)>[
      if (umbrales?.atencionM != null) (umbrales!.atencionM!, _colorAtencion, 'Atención'),
      if (umbrales?.alertaM != null) (umbrales!.alertaM!, _colorAlerta, 'Alerta'),
      if (umbrales?.evacuacionM != null) (umbrales!.evacuacionM!, _colorEvacuacion, 'Evacuación'),
    ];
    final valores = [...puntos.map((p) => p.valorM), ...lineas.map((l) => l.$1)];
    final minY = (valores.reduce(math.min) - 0.3).floorToDouble().clamp(0.0, 20.0);
    final maxY = (valores.reduce(math.max) + 0.6).ceilToDouble();
    final dias = (hasta.difference(desde).inMinutes / 60 / 24).round();
    final cadaDias = dias <= 7 ? 1 : (dias <= 30 ? 5 : 15);
    const estiloEje = TextStyle(fontSize: 13, color: Colors.black);

    return LineChart(
      LineChartData(
        minX: _x(desde),
        maxX: _x(hasta),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(horizontalInterval: 1, verticalInterval: 24.0 * cadaDias),
        borderData: FlBorderData(border: Border.all(color: Colors.black54)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 1,
              getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                  ? const SizedBox.shrink()
                  : SideTitleWidget(meta: meta, child: Text('${v.toInt()} m', style: estiloEje)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 24.0 * cadaDias,
              getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                  ? const SizedBox.shrink()
                  : SideTitleWidget(
                      meta: meta,
                      child: Text(
                        formatoDiaCorto(_fechaDe(v)),
                        style: estiloEje,
                      ),
                    ),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            for (final (y, color, nombre) in lineas)
              HorizontalLine(
                y: y,
                color: color,
                strokeWidth: 2,
                dashArray: [8, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                  labelResolver: (_) => '$nombre ${formatoAltura(y)} m',
                ),
              ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black,
            getTooltipItems: (tocados) => [
              for (final t in tocados)
                LineTooltipItem(
                  '${formatoAltura(t.y)} m\n'
                  '${formatoFecha(_fechaDe(t.x), hasta)}',
                  const TextStyle(color: Colors.white, fontSize: 14),
                ),
            ],
          ),
        ),
        lineBarsData: [
          if (estacion.isNotEmpty)
            LineChartBarData(
              spots: estacion,
              color: _colorEstacion,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          if (prefectura.isNotEmpty)
            // Prefectura mide una vez por día: se dibuja como puntos sueltos.
            LineChartBarData(
              spots: prefectura,
              color: Colors.transparent,
              barWidth: 0.1,
              dotData: FlDotData(
                getDotPainter: (_, _, _, _) =>
                    FlDotCirclePainter(radius: 4.5, color: Colors.white, strokeWidth: 2, strokeColor: Colors.black),
              ),
            ),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Umbrales? umbrales;
  final bool hayPrefectura;

  const _Leyenda({required this.umbrales, required this.hayPrefectura});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyLarge;
    Widget fila(Widget muestra, String texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 36, child: Center(child: muestra)),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: estilo)),
          ]),
        );
    Widget raya(Color c) => Container(width: 30, height: 3, color: c);
    Widget rayaCortada(Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 3, color: c),
          const SizedBox(width: 4),
          Container(width: 9, height: 3, color: c),
        ]);
    final u = umbrales;
    return Column(
      children: [
        fila(raya(_colorEstacion), 'Estación automática (cada 30 minutos)'),
        if (hayPrefectura)
          fila(
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
            ),
            'Prefectura (una lectura por día)',
          ),
        if (u?.atencionM != null) fila(rayaCortada(_colorAtencion), 'Nivel de atención: ${formatoAltura(u!.atencionM!)} m'),
        if (u?.alertaM != null) fila(rayaCortada(_colorAlerta), 'Nivel de alerta: ${formatoAltura(u!.alertaM!)} m'),
        if (u?.evacuacionM != null)
          fila(rayaCortada(_colorEvacuacion), 'Nivel de evacuación: ${formatoAltura(u!.evacuacionM!)} m'),
      ],
    );
  }
}

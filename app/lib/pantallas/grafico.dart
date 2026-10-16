import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';

Color get _colorEstacion => Colores.primario;
Color get _colorAtencion => estiloNivel(Nivel.atencion).oscuro;
Color get _colorAlerta => estiloNivel(Nivel.alerta).oscuro;
Color get _colorEvacuacion => estiloNivel(Nivel.evacuacion).oscuro;
const _rayaAtencion = [3, 4];
const _rayaAlerta = [8, 5];
const _rayaEvacuacion = [16, 5];

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

/// Las lecturas posteriores a [desde].
List<PuntoHistorial> puntosDesde(List<PuntoHistorial> historial, DateTime desde) =>
    historial.where((p) => p.fecha.isAfter(desde)).toList();

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
    if (widget.datos == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Cargando el nivel del río…')],
          ),
        ),
      );
    }
    final historial = widget.datos?.historial ?? const <PuntoHistorial>[];
    final umbrales = widget.datos?.umbrales;
    final ahora = widget.ahora ?? DateTime.now();
    final desde = ahora.subtract(Duration(days: _dias));
    final puntos = puntosDesde(historial, desde);
    final diasConDatos = historial.isEmpty ? 0 : ahora.difference(historial.first.fecha).inDays;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(header: true, child: Text('Altura del río en los últimos días', style: tema.titleLarge)),
        const SizedBox(height: 12),
        // Tope al agrandado de letra: con más, los tres botones no entran en una fila.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 días')),
            ButtonSegment(value: 30, label: Text('30 días')),
            ButtonSegment(value: 90, label: Text('90 días')),
          ],
          selected: {_dias},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _dias = s.first),
        )),
        const SizedBox(height: 12),
        Semantics(liveRegion: true, child: Text(resumenHistorial(puntos), style: tema.bodyLarge)),
        if (puntos.isNotEmpty && diasConDatos < _dias - 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Por ahora hay datos guardados desde el ${formatoDiaCorto(historial.first.fecha)}.',
              style: tema.bodyMedium,
            ),
          ),
        const SizedBox(height: 24),
        if (puntos.isNotEmpty) ...[
          Semantics(
            label: 'Gráfico de la altura del río en los últimos $_dias días. El resumen está antes.',
            excludeSemantics: true,
            // El resumen y la leyenda agrandan la letra sin tope; dentro del gráfico se limita para que los ejes no se pisen.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              // Suelto sobre el fondo, sin tarjeta alrededor.
              child: SizedBox(
                  height: 320, child: GraficoAltura(puntos: puntos, umbrales: umbrales, desde: desde, hasta: ahora)),
            ),
          ),
          const SizedBox(height: 16),
          // Los niveles ya van rotulados sobre su línea: la leyenda solo explica las dos series.
          _Leyenda(
            hayEstacion: puntos.any((p) => p.fuente == 'estacion'),
            hayPrefectura: puntos.any((p) => p.fuente == 'prefectura'),
          ),
          const SizedBox(height: 16),
          Text(
            umbrales != null && !umbrales.validado
                ? 'Fuente: CARU. Los niveles marcados son de referencia.'
                : 'Fuente: CARU.',
            style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria),
          ),
        ],
      ],
    );
  }
}

/// Gráfico de la altura con las líneas de los niveles. Lo usan la pestaña
/// Gráfico y, en versión [compacto], la pantalla de Inicio.
///
/// El compacto es para mirar de un vistazo: solo alerta y evacuación (con
/// rótulos cortos), la zona por encima de alerta sombreada, un punto en el
/// último valor y nada que se toque (sin cartelito).
class GraficoAltura extends StatelessWidget {
  final List<PuntoHistorial> puntos;
  final Umbrales? umbrales;
  final DateTime desde;
  final DateTime hasta;
  final bool compacto;

  const GraficoAltura({
    super.key,
    required this.puntos,
    required this.umbrales,
    required this.desde,
    required this.hasta,
    this.compacto = false,
  });

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
    // Lo que queda detrás del gráfico: el fondo de la app o la tarjeta de Inicio.
    final detras = compacto ? Colores.superficie : Colores.fondo;

    // Cada nivel tiene su color y además un punteado distinto (no depender solo del color).
    final lineas = <(double, Color, String, List<int>)>[
      if (!compacto && umbrales?.atencionM != null)
        (umbrales!.atencionM!, _colorAtencion, 'Atención', _rayaAtencion),
      if (umbrales?.alertaM != null) (umbrales!.alertaM!, _colorAlerta, 'Alerta', _rayaAlerta),
      if (umbrales?.evacuacionM != null) (umbrales!.evacuacionM!, _colorEvacuacion, 'Evacuación', _rayaEvacuacion),
    ];
    final letraEtiqueta = MediaQuery.textScalerOf(context).scale(compacto ? 12 : 16);
    final valores = [...puntos.map((p) => p.valorM), ...lineas.map((l) => l.$1)];
    final minY = (valores.reduce(math.min) - 0.3).floorToDouble().clamp(0.0, 20.0);
    final maxY = (valores.reduce(math.max) + 0.6).ceilToDouble();
    final dias = (hasta.difference(desde).inMinutes / 60 / 24).round();
    final cadaDias = compacto ? 2 : (dias <= 7 ? 1 : (dias <= 30 ? 5 : 15));
    final estiloEje =
        TextStyle(fontSize: compacto ? 12 : 14, color: compacto ? Colores.tintaSecundaria : Colores.tinta);
    final alerta = umbrales?.alertaM;

    return LineChart(
      LineChartData(
        minX: _x(desde),
        maxX: _x(hasta),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          horizontalInterval: 1,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colores.divisor, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          border: Border(
            bottom: BorderSide(color: Colores.bordeControl),
          ),
        ),
        // En el compacto, la zona por encima de alerta va apenas sombreada.
        rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
          if (compacto && alerta != null && alerta < maxY)
            HorizontalRangeAnnotation(y1: alerta, y2: maxY, color: const Color(0xFFEF6C00).withValues(alpha: 0.10)),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compacto ? 40 : 50,
              interval: 1,
              getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                  ? const SizedBox.shrink()
                  : SideTitleWidget(meta: meta, child: Text('${v.toInt()} m', style: estiloEje)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compacto ? 26 : 38,
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
            for (final (y, color, nombre, raya) in lineas)
              HorizontalLine(
                y: y,
                color: color,
                strokeWidth: compacto ? 1.5 : 2,
                dashArray: raya,
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: letraEtiqueta),
                  // En el compacto, rótulo corto: "Alerta 4,39".
                  labelResolver: (_) => compacto ? '$nombre ${formatoAltura(y)}' : '$nombre ${formatoAltura(y)} m',
                ),
              ),
          ],
        ),
        lineTouchData: compacto
            ? const LineTouchData(enabled: false)
            : LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Colores.tinta,
                  getTooltipItems: (tocados) => [
                    for (final t in tocados)
                      LineTooltipItem(
                        '${formatoAltura(t.y)} m\n'
                        '${formatoFecha(_fechaDe(t.x), hasta)}',
                        TextStyle(color: Colores.fondo, fontSize: 16),
                      ),
                  ],
                ),
              ),
        lineBarsData: [
          if (estacion.isNotEmpty)
            LineChartBarData(
              spots: estacion,
              color: _colorEstacion,
              barWidth: compacto ? 2.5 : 3,
              // En el compacto, un punto marca el último valor de la estación.
              dotData: compacto
                  ? FlDotData(
                      checkToShowDot: (spot, barra) => spot == barra.spots.last,
                      getDotPainter: (_, _, _, _) =>
                          FlDotCirclePainter(radius: 5, color: _colorEstacion, strokeWidth: 2, strokeColor: detras),
                    )
                  : const FlDotData(show: false),
              belowBarData:
                  BarAreaData(show: true, color: _colorEstacion.withValues(alpha: compacto ? 0.10 : 0.08)),
            ),
          if (prefectura.isNotEmpty)
            // Prefectura mide una vez por día: se dibuja como puntos sueltos.
            LineChartBarData(
              spots: prefectura,
              color: Colors.transparent,
              barWidth: 0.1,
              dotData: FlDotData(
                getDotPainter: (_, _, _, _) =>
                    FlDotCirclePainter(radius: 4.5, color: detras, strokeWidth: 2, strokeColor: Colores.tinta),
              ),
            ),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final bool hayEstacion;
  final bool hayPrefectura;

  const _Leyenda({required this.hayEstacion, required this.hayPrefectura});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    Widget entrada(Widget muestra, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [muestra, const SizedBox(width: 8), Flexible(child: Text(texto, style: estilo))],
        );
    return Wrap(
      spacing: 24,
      runSpacing: 8,
      children: [
        if (hayEstacion) entrada(Container(width: 24, height: 3, color: _colorEstacion), 'Estación automática'),
        if (hayPrefectura)
          entrada(
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colores.fondo,
                shape: BoxShape.circle,
                border: Border.all(color: Colores.tinta, width: 2),
              ),
            ),
            'Prefectura (una por día)',
          ),
      ],
    );
  }
}

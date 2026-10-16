import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tres capas de agua que se mueven despacio, en el color del nivel. Son pura
/// decoración: el lector de pantalla no las ve y la información sigue en los
/// textos.
///
/// Gastan lo mínimo: se pintan en su propia capa (RepaintBoundary), no se
/// mueven si el teléfono pide menos animaciones, ni cuando la pestaña no está a
/// la vista (TickerMode) ni con la app en segundo plano.
class OlasNivel extends StatefulWidget {
  /// Las pruebas lo apagan para que pumpAndSettle no espere a un movimiento
  /// que no termina nunca. En la app queda siempre en true.
  static bool animar = true;

  /// Una vuelta completa de las olas.
  static const ciclo = Duration(seconds: 12);

  final Color color;

  /// Opacidad de cada capa, de atrás hacia adelante.
  final List<double> opacidades;

  const OlasNivel({super.key, required this.color, required this.opacidades});

  @override
  State<OlasNivel> createState() => _OlasNivelState();
}

class _OlasNivelState extends State<OlasNivel> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _movimiento = AnimationController(vsync: this, duration: OlasNivel.ciclo);
  bool _enPrimerPlano = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final estado = WidgetsBinding.instance.lifecycleState;
    _enPrimerPlano = estado == null || estado == AppLifecycleState.resumed || estado == AppLifecycleState.inactive;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _decidir();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    _enPrimerPlano = estado == AppLifecycleState.resumed || estado == AppLifecycleState.inactive;
    _decidir();
  }

  /// Quietas (un cuadro fijo) si se piden menos animaciones o la app no está a la vista.
  void _decidir() {
    final mover = OlasNivel.animar && _enPrimerPlano && !MediaQuery.disableAnimationsOf(context);
    if (mover && !_movimiento.isAnimating) {
      _movimiento.repeat();
    } else if (!mover && _movimiento.isAnimating) {
      _movimiento.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _movimiento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _PintorOlas(_movimiento, widget.color, widget.opacidades),
            size: Size.infinite,
          ),
        ),
      );
}

class _PintorOlas extends CustomPainter {
  final Animation<double> movimiento;
  final Color color;
  final List<double> opacidades;

  _PintorOlas(this.movimiento, this.color, this.opacidades) : super(repaint: movimiento);

  // Cresta de cada capa medida desde arriba, para una banda de 64 dp, con su
  // amplitud y su sentido de avance (vueltas enteras por ciclo: no salta al repetir).
  static const _capas = [(24.0, 8.0, 1), (35.0, 6.0, -1), (46.0, 5.0, 1)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    // Bandas bajas: todo se achica. Bandas altas: las crestas quedan arriba y el agua llena hacia abajo.
    final escala = math.min(1.0, h / 64);
    final largo = w / 1.6;
    final vuelta = movimiento.value * 2 * math.pi;
    for (var i = 0; i < _capas.length && i < opacidades.length; i++) {
      final a = opacidades[i];
      if (a <= 0) continue;
      final (cresta, amplitud, sentido) = _capas[i];
      final base = cresta * escala, amp = amplitud * escala;
      final fase = vuelta * sentido + i * 1.7;
      final camino = Path();
      for (var x = 0.0; x <= w + 4; x += 4) {
        final y = base +
            math.sin(x / largo * 2 * math.pi + fase) * amp +
            math.sin(x / (largo * 0.55) * 2 * math.pi - 2 * fase) * amp * 0.35;
        x == 0 ? camino.moveTo(x, y) : camino.lineTo(x, y);
      }
      camino
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(camino, Paint()..color = color.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_PintorOlas viejo) =>
      viejo.color != color || viejo.opacidades.join() != opacidades.join() || viejo.movimiento != movimiento;
}

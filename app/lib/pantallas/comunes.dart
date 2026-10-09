import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';

/// Abre un enlace (página, PDF o teléfono) fuera de la app. Si no se puede, lo dice.
Future<void> abrirEnlace(BuildContext context, String url) async {
  final mensajes = ScaffoldMessenger.of(context);
  var abierto = false;
  try {
    abierto = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!abierto) {
    mensajes.showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace desde este teléfono.')));
  }
}

enum TipoRecuadro { advertencia, informacion, sinConexion }

/// Recuadro de aviso: banda de color a la izquierda, ícono y texto (no depende
/// solo del color). Hay tres tipos y ninguno usa los colores de nivel del río.
class Recuadro extends StatelessWidget {
  final IconData icono;
  final String texto;
  final TipoRecuadro tipo;

  /// Botón opcional debajo del texto (por ejemplo "Reintentar").
  final Widget? accion;

  /// Sin esquinas redondeadas ni margen, para ir pegado dentro de otra tarjeta.
  final bool integrado;

  const Recuadro({
    super.key,
    required this.icono,
    required this.texto,
    this.tipo = TipoRecuadro.advertencia,
    this.accion,
    this.integrado = false,
  });

  @override
  Widget build(BuildContext context) {
    final (fondo, banda) = switch (tipo) {
      TipoRecuadro.advertencia => (const Color(0xFFFFF4D6), const Color(0xFF7A4A00)),
      TipoRecuadro.informacion => (Colores.primarioSuave, Colores.primario),
      TipoRecuadro.sinConexion => (const Color(0xFFE9ECEF), const Color(0xFF424242)),
    };
    final contenido = Material(
      color: fondo,
      clipBehavior: Clip.antiAlias,
      shape: integrado
          ? const RoundedRectangleBorder()
          : const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: banda, width: 6))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: banda, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(texto, style: Theme.of(context).textTheme.bodyLarge), ?accion],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return integrado ? contenido : Padding(padding: const EdgeInsets.only(bottom: 12), child: contenido);
  }
}

/// Deslinde de responsabilidad: la app es una ayuda a la comunidad, sin vínculo
/// con organismos oficiales. Va en Inicio y en "Qué hacer".
class AvisoOficial extends StatelessWidget {
  const AvisoOficial({super.key});

  @override
  Widget build(BuildContext context) => const Recuadro(
        icono: Icons.info,
        tipo: TipoRecuadro.informacion,
        texto: 'Esta app es una ayuda a la comunidad. No tiene vínculo con ningún organismo ni canal oficial '
            'y no reemplaza la alerta oficial. Ante cualquier duda, comunicate con los canales oficiales: '
            'el Cecoed (centro de emergencias de Paysandú) o el Sinae.',
      );
}

/// Regla horizontal que muestra dónde está el río respecto de los niveles de
/// alerta y evacuación. Solo usa la altura publicada y los umbrales: no dibuja
/// pronósticos ni valores estimados. Si falta un umbral, no se marca.
class EscalaNiveles extends StatelessWidget {
  final double alturaM;
  final Umbrales umbrales;
  final String descripcion; // para el lector de pantalla

  const EscalaNiveles({super.key, required this.alturaM, required this.umbrales, required this.descripcion});

  /// Marcas a dibujar: (valor, nivel), solo las que tienen valor.
  static List<(double, Nivel)> marcas(Umbrales u) => [
        if (u.atencionM != null) (u.atencionM!, Nivel.atencion),
        if (u.alertaM != null) (u.alertaM!, Nivel.alerta),
        if (u.evacuacionM != null) (u.evacuacionM!, Nivel.evacuacion),
      ];

  @override
  Widget build(BuildContext context) {
    final lista = marcas(umbrales);
    if (lista.isEmpty) return const SizedBox.shrink();
    final minimo = alturaM < 0 ? alturaM.floorToDouble() : 0.0;
    final maximo = math.max(lista.map((m) => m.$1).reduce(math.max).ceilToDouble() + 1, (alturaM + 0.5).ceilToDouble());
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: descripcion,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: CustomPaint(
              painter: _PintorEscala(
                altura: alturaM,
                minimo: minimo,
                maximo: maximo,
                marcas: [for (final (valor, nivel) in lista) (valor, estiloNivel(nivel).oscuro)],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Rótulos debajo, en el mismo orden que las marcas; se apilan si no entran.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final (valor, nivel) in lista)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 5, height: 18, color: estiloNivel(nivel).oscuro),
                    const SizedBox(width: 8),
                    Text(
                      '${estiloNivel(nivel).nombre} ${formatoAltura(valor)} m',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PintorEscala extends CustomPainter {
  final double altura, minimo, maximo;
  final List<(double, Color)> marcas;

  _PintorEscala({required this.altura, required this.minimo, required this.maximo, required this.marcas});

  @override
  void paint(Canvas canvas, Size size) {
    double x(double metros) => ((metros - minimo) / (maximo - minimo)).clamp(0.0, 1.0) * size.width;
    const arriba = 14.0, alto = 14.0;
    final barra = RRect.fromLTRBR(0, arriba, size.width, arriba + alto, const Radius.circular(7));
    canvas.drawRRect(barra, Paint()..color = Colores.divisor);
    // Relleno hasta la altura actual.
    canvas.save();
    canvas.clipRRect(barra);
    canvas.drawRect(Rect.fromLTRB(0, arriba, x(altura), arriba + alto), Paint()..color = Colores.primario);
    canvas.restore();
    canvas.drawRRect(barra, Paint()
      ..color = Colores.bordeControl
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    // Marcas de los niveles: sobresalen de la barra.
    for (final (valor, color) in marcas) {
      final px = x(valor).clamp(2.5, size.width - 2.5);
      canvas.drawRect(Rect.fromLTRB(px - 2.5, arriba - 6, px + 2.5, arriba + alto + 8), Paint()..color = color);
    }
    // Puntero: triángulo sobre la barra en la altura actual.
    final px = x(altura).clamp(8.0, size.width - 8.0);
    canvas.drawPath(
      Path()
        ..moveTo(px - 8, 0)
        ..lineTo(px + 8, 0)
        ..lineTo(px, 12)
        ..close(),
      Paint()..color = Colores.tinta,
    );
  }

  @override
  bool shouldRepaint(_PintorEscala o) =>
      o.altura != altura || o.minimo != minimo || o.maximo != maximo || o.marcas.length != marcas.length;
}

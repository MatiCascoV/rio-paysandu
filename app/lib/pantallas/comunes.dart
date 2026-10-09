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

/// Línea fina que separa bloques sueltos, con aire arriba y abajo.
class Separador extends StatelessWidget {
  final double arriba;
  final double abajo;

  const Separador({super.key, this.arriba = 16, this.abajo = 16});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: arriba, bottom: abajo),
        child: const Divider(),
      );
}

/// Aviso ámbar: el único recuadro que queda. Se usa solo cuando algo anda mal
/// (dato viejo, dato dudoso, falta un permiso). Ícono y texto, no solo color.
class Recuadro extends StatelessWidget {
  final IconData icono;
  final String texto;

  const Recuadro({super.key, required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    final fondo = Colores.oscuro ? const Color(0xFF3A2E12) : const Color(0xFFFFF4D6);
    final colorIcono = Colores.oscuro ? const Color(0xFFFFC857) : const Color(0xFF7A4A00);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: fondo, borderRadius: radioSuperficie),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: colorIcono, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

/// Deslinde de responsabilidad completo. Va en "Qué hacer".
const textoDeslinde = 'Esta app es una ayuda a la comunidad. No tiene vínculo con ningún organismo ni canal oficial '
    'y no reemplaza la alerta oficial. Ante cualquier duda, comunicate con los canales oficiales: '
    'el Cecoed (centro de emergencias de Paysandú) o el Sinae.';

/// Deslinde corto, para el pie de Inicio.
const textoDeslindeCorto = 'App de ayuda a la comunidad, sin vínculo oficial. No reemplaza la alerta oficial.';

/// Escalera de niveles: los umbrales de mayor a menor y, intercalada donde
/// corresponde, la altura de ahora. Los peldaños están en orden, no a escala,
/// por eso cada uno lleva su altura escrita. Solo usa datos publicados; si
/// falta un umbral, ese peldaño no se dibuja.
class EscaleraNiveles extends StatelessWidget {
  final double alturaM;
  final Umbrales umbrales;

  /// Dato de hace varias horas: se dice "Último dato" y se atenúa.
  final bool viejo;

  /// Texto completo para el lector de pantalla.
  final String descripcion;

  const EscaleraNiveles({
    super.key,
    required this.alturaM,
    required this.umbrales,
    required this.descripcion,
    this.viejo = false,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final lista = umbralesOrdenados(umbrales);
    // La fila de ahora va arriba de todos los umbrales que el río ya alcanzó.
    final posicion = lista.indexWhere((u) => (alturaM * 100).round() >= (u.$2 * 100).round());
    final indiceAhora = posicion == -1 ? lista.length : posicion;
    final total = lista.length + 1;
    final acento = viejo ? Colores.tintaSecundaria : Colores.primario;
    final cifras = tema.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final nota = [
      'Medido en el puerto de Paysandú: no es la altura del agua en tu calle.',
      if (!umbrales.validado) 'Los niveles son de referencia; el Cecoed todavía los está revisando.',
    ].join(' ');

    Widget tramo(bool visible, bool agua) => Expanded(
          child: visible
              ? Container(width: agua ? 4 : 2, color: agua ? acento : Colores.bordeControl)
              : const SizedBox.shrink(),
        );

    Widget fila(int i) {
      final esAhora = i == indiceAhora;
      // El riel es fino y gris por encima del agua, y grueso y azul desde "ahora" hacia abajo.
      final riel = SizedBox(
        width: 24,
        child: Column(
          children: [
            tramo(i > 0, i > indiceAhora),
            if (esAhora)
              Container(width: 16, height: 16, decoration: BoxDecoration(color: acento, shape: BoxShape.circle))
            else
              Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: estiloNivel(lista[i > indiceAhora ? i - 1 : i].$1).oscuro,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            tramo(true, i >= indiceAhora),
          ],
        ),
      );
      final Widget contenido;
      if (esAhora) {
        final falta = textoFalta(alturaM, umbrales, viejo: viejo);
        contenido = Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(child: Text(viejo ? 'Último dato' : 'Ahora', style: tema.titleMedium?.copyWith(color: acento))),
                  Text('${formatoAltura(alturaM)} m', style: cifras),
                ],
              ),
              if (falta != null) Text(falta, style: tema.bodyMedium),
            ],
          ),
        );
      } else {
        final (nivel, valor) = lista[i > indiceAhora ? i - 1 : i];
        contenido = Row(
          children: [
            Expanded(child: Text(estiloNivel(nivel).nombre, style: tema.bodyLarge)),
            Text('${formatoAltura(valor)} m', style: cifras),
          ],
        );
      }
      return Container(
        constraints: BoxConstraints(minHeight: esAhora ? 76 : 52),
        decoration: esAhora
            ? BoxDecoration(color: Colores.superficieAlta, borderRadius: BorderRadius.circular(12))
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [riel, const SizedBox(width: 12), Expanded(child: contenido)],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$descripcion $nota',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        decoration: BoxDecoration(color: Colores.superficie, borderRadius: radioSuperficie),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < total; i++) fila(i),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(nota, style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
            ),
          ],
        ),
      ),
    );
  }
}

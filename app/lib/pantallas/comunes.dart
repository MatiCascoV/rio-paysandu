import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../enlaces.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';

/// Abre una página o PDF de un sitio permitido fuera de la app (los teléfonos
/// van por llamar()). Si no se puede, lo dice.
Future<void> abrirEnlace(BuildContext context, String url) async {
  final mensajes = ScaffoldMessenger.of(context);
  final uri = uriPermitida(url);
  var abierto = false;
  if (uri != null) {
    try {
      abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
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

/// Deslinde corto, para el pie de Inicio (lleva a "Qué hacer", donde está completo).
const textoDeslindeCorto = 'App comunitaria, sin vínculo oficial. No reemplaza la alerta oficial';

/// "Ver qué hacer" de ancho completo, en el color del nivel.
class BotonQueHacer extends StatelessWidget {
  final Nivel nivel;
  final VoidCallback? alTocar;

  const BotonQueHacer({super.key, required this.nivel, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final (fondo, texto) = ColoresNivel.boton(nivel);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: fondo,
        foregroundColor: texto,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
      ),
      onPressed: alTocar,
      child: const Text('Ver qué hacer'),
    );
  }
}

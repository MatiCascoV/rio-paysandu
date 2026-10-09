import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Recuadro de aviso con ícono y texto (no depende solo del color).
class Recuadro extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color fondo;
  final Color colorTexto;

  const Recuadro({
    super.key,
    required this.icono,
    required this.texto,
    this.fondo = const Color(0xFFFFF3C4),
    this.colorTexto = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black54),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: colorTexto, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(texto, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colorTexto)),
          ),
        ],
      ),
    );
  }
}

/// Aviso fijo: la app informa, la alerta oficial es del Sinae / Cecoed.
class AvisoOficial extends StatelessWidget {
  const AvisoOficial({super.key});

  @override
  Widget build(BuildContext context) => const Recuadro(
        icono: Icons.info,
        fondo: Color(0xFFE3F2FD),
        texto: 'Esta app es un canal de información de la Intendencia de Paysandú. '
            'No reemplaza la alerta oficial, que la dan el Sinae y el Cecoed (el centro de emergencias de Paysandú).',
      );
}

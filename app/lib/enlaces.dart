/// Qué enlaces y teléfonos puede abrir la app. Las direcciones llegan en los
/// JSON publicados (que a su vez salen de CARU por HTTP sin cifrar), así que
/// solo se abren las de los sitios conocidos de assets/config.json.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Orígenes (esquema, sitio y puerto) permitidos. Vacío hasta que se carga la
/// configuración: sin lista no se abre nada.
Set<(String, String, int)> _origenes = const {};

/// Carga la lista de orígenes permitidos (por ejemplo "https://caru.org.uy").
/// Las entradas que no son un origen http/https limpio se ignoran.
void permitirOrigenes(Iterable<String> origenes) {
  _origenes = {
    for (final o in origenes) ?_origen(Uri.tryParse(o.trim())),
  };
}

(String, String, int)? _origen(Uri? u) {
  if (u == null || !u.hasAuthority || u.host.isEmpty || u.userInfo.isNotEmpty) return null;
  final esquema = u.scheme.toLowerCase();
  if (esquema != 'https' && esquema != 'http') return null;
  // u.port da 443 u 80 si la dirección no lo dice.
  return (esquema, u.host.toLowerCase(), u.port);
}

/// ¿Se puede mostrar y abrir este enlace? Compara esquema, sitio y puerto
/// exactos (no alcanza con que el texto empiece igual) y rechaza usuario@sitio.
bool enlacePermitido(String? url) => uriPermitida(url) != null;

/// La dirección ya analizada y recortada, lista para abrir, o null si no está
/// permitida. Se abre esta, no el texto original.
Uri? uriPermitida(String? url) {
  if (url == null || url.length > 2000) return null;
  final uri = Uri.tryParse(url.trim());
  final o = _origen(uri);
  if (uri == null || o == null || !_origenes.contains(o)) return null;
  // Si el mismo sitio también está permitido por https, se abre por https: no se
  // usa http sin cifrar donde existe la versión cifrada.
  if (o.$1 == 'http' && _origenes.contains(('https', o.$2, uri.hasPort && uri.port != 80 ? uri.port : 443))) {
    return uri.replace(scheme: 'https');
  }
  return uri;
}

/// ¿Este enlace permitido se abriría por http, sin cifrar? (CARU publica la
/// página de alturas solo por http.) La pantalla lo avisa junto al botón.
bool enlaceSinCifrar(String? url) => uriPermitida(url)?.scheme == 'http';

/// El número listo para "tel:" (solo dígitos, con un + inicial opcional), o
/// null si trae cualquier otra cosa. Los espacios de formato se quitan.
String? numeroParaLlamar(String numero) {
  final n = numero.replaceAll(' ', '');
  return RegExp(r'^\+?[0-9]{1,15}$').hasMatch(n) ? n : null;
}

/// Abre el marcador del teléfono con [numero]. Si no se puede, lo dice.
Future<void> llamar(BuildContext context, String numero) async {
  final mensajes = ScaffoldMessenger.of(context);
  final n = numeroParaLlamar(numero);
  var abierto = false;
  if (n != null) {
    try {
      abierto = await launchUrl(Uri(scheme: 'tel', path: n));
    } catch (_) {}
  }
  if (!abierto) {
    mensajes.showSnackBar(const SnackBar(content: Text('No se pudo llamar desde este teléfono.')));
  }
}

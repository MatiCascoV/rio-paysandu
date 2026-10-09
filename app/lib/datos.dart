/// Descarga los JSON publicados y guarda una copia en el teléfono, para que la
/// app funcione sin conexión mostrando el último dato con su fecha.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos.dart';

class Contacto {
  final String nombre;
  final String telefono;
  final String? detalle;
  const Contacto(this.nombre, this.telefono, this.detalle);
}

/// Configuración de la app (assets/config.json). Acá viven la dirección de los
/// datos y los teléfonos: nada de eso está escrito en el código.
class Config {
  final String urlBase;
  final int horasAvisoDatoViejo;
  final int horasSinDato;
  final List<Contacto> contactos;

  const Config({
    required this.urlBase,
    this.horasAvisoDatoViejo = 6,
    this.horasSinDato = 48,
    this.contactos = const [],
  });

  static Config desdeJson(Map<String, dynamic> j) => Config(
        // --dart-define=URL_BASE=... permite probar contra datos de prueba.
        urlBase: const String.fromEnvironment('URL_BASE', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('URL_BASE')
            : j['url_base'] as String,
        horasAvisoDatoViejo: j['horas_aviso_dato_viejo'] as int? ?? 6,
        horasSinDato: j['horas_sin_dato'] as int? ?? 48,
        contactos: [
          for (final c in (j['contactos'] as List? ?? const []))
            Contacto(c['nombre'] as String, c['telefono'] as String, c['detalle'] as String?),
        ],
      );

  static Future<Config> cargar() async =>
      desdeJson(jsonDecode(await rootBundle.loadString('assets/config.json')) as Map<String, dynamic>);
}

class Datos {
  final Actual? actual;
  final Umbrales? umbrales;
  final List<PuntoHistorial> historial;

  /// true si no se pudo descargar y lo que se muestra es la copia guardada.
  final bool sinConexion;

  const Datos({this.actual, this.umbrales, this.historial = const [], this.sinConexion = false});
}

class Repositorio {
  final String urlBase;
  final http.Client _cliente;

  Repositorio(this.urlBase, {http.Client? cliente}) : _cliente = cliente ?? http.Client();

  static const _archivos = ['actual', 'umbrales', 'historial'];

  /// Baja un archivo; si lo consigue lo guarda. Devuelve (json, vinoDeLaRed).
  Future<(Object?, bool)> _leer(String nombre, SharedPreferences prefs, bool usarRed) async {
    if (usarRed) {
      try {
        final r = await _cliente.get(Uri.parse('$urlBase$nombre.json')).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          final texto = utf8.decode(r.bodyBytes);
          final json = jsonDecode(texto); // si no es JSON válido, no se guarda
          await prefs.setString('cache_$nombre', texto);
          return (json, true);
        }
      } catch (_) {
        // sin conexión, tiempo agotado o respuesta rota: seguimos con la copia
      }
    }
    final guardado = prefs.getString('cache_$nombre');
    if (guardado == null) return (null, false);
    try {
      return (jsonDecode(guardado), false);
    } catch (_) {
      return (null, false);
    }
  }

  Future<Datos> cargar({bool usarRed = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await Future.wait(_archivos.map((a) => _leer(a, prefs, usarRed)));
    return Datos(
      actual: Actual.desdeJson(r[0].$1),
      umbrales: Umbrales.desdeJson(r[1].$1),
      historial: PuntoHistorial.listaDesdeJson(r[2].$1),
      sinConexion: usarRed && !r[0].$2,
    );
  }
}

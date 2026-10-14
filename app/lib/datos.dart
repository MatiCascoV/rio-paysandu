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

  /// Aclaración corta que va bajo el número (por ejemplo "celular").
  final String? detalle;

  /// Título del grupo en "Qué hacer" (por ejemplo "De 6 a 18 horas · Cecoed Paysandú").
  final String grupo;
  const Contacto(this.nombre, this.telefono, this.detalle, [this.grupo = '']);
}

/// Configuración de la app (assets/config.json). Acá viven la dirección de los
/// datos y los teléfonos: nada de eso está escrito en el código.
class Config {
  final String urlBase;
  final int horasAvisoDatoViejo;
  final int horasSinDato;
  final List<Contacto> contactos;

  /// Sitios cuyos enlaces se pueden abrir (esquema, sitio y puerto).
  final List<String> enlacesPermitidos;

  const Config({
    required this.urlBase,
    this.horasAvisoDatoViejo = 6,
    this.horasSinDato = 48,
    this.contactos = const [],
    this.enlacesPermitidos = const [],
  });

  static Config desdeJson(Map<String, dynamic> j) => Config(
        // --dart-define=URL_BASE=... permite probar contra datos de prueba.
        urlBase: const String.fromEnvironment('URL_BASE', defaultValue: '').isNotEmpty
            ? const String.fromEnvironment('URL_BASE')
            : j['url_base'] as String,
        horasAvisoDatoViejo: (j['horas_aviso_dato_viejo'] as num?)?.toInt() ?? 6,
        horasSinDato: (j['horas_sin_dato'] as num?)?.toInt() ?? 48,
        contactos: [
          for (final c in (j['contactos'] as List? ?? const []))
            Contacto(c['nombre'] as String, c['telefono'] as String, c['detalle'] as String?, c['grupo'] as String? ?? ''),
        ],
        enlacesPermitidos: [
          for (final e in (j['enlaces_permitidos'] as List? ?? const [])) e as String,
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

  /// Tope de cada respuesta: los archivos reales pesan unos pocos KB.
  static const bytesMaximos = 2 * 1024 * 1024;

  /// ¿El JSON tiene la forma esperada? Una respuesta rara no pisa la copia buena.
  static bool esValido(String nombre, Object? json) => switch (nombre) {
        'actual' => json is Map &&
            json['nivel'] is String &&
            Actual.desdeJson(json) != null &&
            // Si trae altura, tiene que ser una altura posible.
            (json['altura_actual'] == null || Lectura.desdeJson(json['altura_actual']) != null),
        'umbrales' => Umbrales.desdeJson(json) != null,
        'historial' => json is List,
        _ => false,
      };

  /// Baja el archivo cortando apenas pasa de [bytesMaximos].
  Future<List<int>?> _bajar(String nombre) async {
    final r = await _cliente.send(http.Request('GET', Uri.parse('$urlBase$nombre.json')));
    if (r.statusCode != 200 || (r.contentLength ?? 0) > bytesMaximos) return null;
    final bytes = <int>[];
    await for (final parte in r.stream) {
      bytes.addAll(parte);
      if (bytes.length > bytesMaximos) return null;
    }
    return bytes;
  }

  /// Baja un archivo; si lo consigue y es válido lo guarda. Devuelve (json, vinoDeLaRed).
  Future<(Object?, bool)> _leer(String nombre, SharedPreferences prefs, bool usarRed) async {
    if (usarRed) {
      try {
        final bytes = await _bajar(nombre).timeout(const Duration(seconds: 15));
        if (bytes != null) {
          final texto = utf8.decode(bytes);
          final json = jsonDecode(texto); // si no es JSON válido, no se guarda
          if (esValido(nombre, json)) {
            await prefs.setString('cache_$nombre', texto);
            return (json, true);
          }
        }
      } catch (_) {
        // sin conexión, tiempo agotado o respuesta rota: seguimos con la copia
      }
    }
    final guardado = prefs.getString('cache_$nombre');
    if (guardado == null) return (null, false);
    try {
      final json = jsonDecode(guardado);
      return (esValido(nombre, json) ? json : null, false);
    } catch (_) {
      return (null, false);
    }
  }

  /// [soloActual] lo usa la tarea en segundo plano, que no necesita el historial.
  Future<Datos> cargar({bool usarRed = true, bool soloActual = false}) async {
    final prefs = await SharedPreferences.getInstance();
    // La tarea en segundo plano corre aparte y pudo haber guardado datos más nuevos.
    await prefs.reload();
    final r = await Future.wait(_archivos.map((a) => _leer(a, prefs, usarRed && !(soloActual && a != 'actual'))));
    return Datos(
      actual: Actual.desdeJson(r[0].$1),
      umbrales: Umbrales.desdeJson(r[1].$1),
      historial: PuntoHistorial.listaDesdeJson(r[2].$1),
      sinConexion: usarRed && !r[0].$2,
    );
  }
}

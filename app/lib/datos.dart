/// Descarga los JSON publicados y guarda una copia en el teléfono, para que la
/// app funcione sin conexión mostrando el último dato con su fecha.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

  /// Tiempo máximo para bajar cada archivo.
  final Duration tiempoMaximo;

  /// true con los datos de ejemplo: no se lee ni se guarda la copia en el
  /// teléfono (los datos inventados no pueden pisar los reales) y la app no
  /// revisa el nivel para avisar.
  final bool soloLectura;

  Repositorio(this.urlBase,
      {http.Client? cliente, this.tiempoMaximo = const Duration(seconds: 15), this.soloLectura = false})
      : _cliente = cliente ?? http.Client();

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

  /// Baja el archivo cortando apenas pasa de [bytesMaximos]. Pasado
  /// [tiempoMaximo] se aborta el pedido y se suelta la conexión: nada queda
  /// leyendo en segundo plano. Devuelve null si la respuesta no sirve.
  Future<List<int>?> _bajar(String nombre) async {
    final abortar = Completer<void>();
    final listo = Completer<List<int>?>();
    StreamSubscription<List<int>>? suscripcion;
    void terminar(List<int>? bytes, [Object? error]) {
      if (listo.isCompleted) return;
      error == null ? listo.complete(bytes) : listo.completeError(error);
    }

    final reloj = Timer(tiempoMaximo, () {
      if (!abortar.isCompleted) abortar.complete(); // corta el pedido en curso
      suscripcion?.cancel();
      terminar(null, TimeoutException('Sin respuesta', tiempoMaximo));
    });
    try {
      final pedido = http.AbortableRequest('GET', Uri.parse('$urlBase$nombre.json'), abortTrigger: abortar.future);
      final enviado = _cliente.send(pedido);
      final http.StreamedResponse r;
      try {
        // listo solo termina antes que el envío si vence el tiempo (con error).
        r = await Future.any([enviado, listo.future.then((_) => enviado)]);
      } catch (_) {
        // Si la respuesta igual llega tarde, se suelta sin leer.
        unawaited(enviado.then((r) => r.stream.listen(null).cancel(), onError: (_) {}));
        rethrow;
      }
      if (r.statusCode != 200 || (r.contentLength ?? 0) > bytesMaximos) {
        await r.stream.listen(null).cancel(); // se suelta sin leer
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      suscripcion = r.stream.listen(
        (parte) {
          bytes.add(parte);
          if (bytes.length > bytesMaximos) {
            suscripcion?.cancel();
            terminar(null);
          }
        },
        onError: (Object e) => terminar(null, e),
        onDone: () => terminar(bytes.takeBytes()),
        cancelOnError: true,
      );
      return await listo.future;
    } finally {
      reloj.cancel();
    }
  }

  /// Baja un archivo; si lo consigue y es válido lo guarda. Devuelve (json, vinoDeLaRed).
  Future<(Object?, bool)> _leer(String nombre, SharedPreferences prefs, bool usarRed) async {
    if (usarRed) {
      try {
        final bytes = await _bajar(nombre);
        if (bytes != null) {
          final texto = utf8.decode(bytes);
          final json = jsonDecode(texto); // si no es JSON válido, no se guarda
          if (esValido(nombre, json)) {
            if (!soloLectura) await prefs.setString('cache_$nombre', texto);
            return (json, true);
          }
        }
      } catch (_) {
        // sin conexión, tiempo agotado o respuesta rota: seguimos con la copia
      }
    }
    if (soloLectura) return (null, false);
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
    final umbrales = Umbrales.desdeJson(r[1].$1);
    // El actual conoce los umbrales para cruzar `nivel` con la altura.
    final actual = Actual.desdeJson(r[0].$1)?.conUmbrales(umbrales);
    return Datos(
      actual: actual,
      umbrales: umbrales,
      historial: PuntoHistorial.listaDesdeJson(r[2].$1, generado: actual?.generado),
      sinConexion: usarRed && !r[0].$2,
    );
  }
}

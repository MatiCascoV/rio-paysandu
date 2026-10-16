/// Datos de ejemplo por nivel, para revisar el diseño y sacar capturas sin
/// esperar a que el río llegue a cada nivel. Solo se usan si la app se compila
/// con `--dart-define=DATOS_EJEMPLO=nivel` (normal, atencion, alerta,
/// evacuacion o sindato; con "url" se elige con `?ejemplo=nivel` en la web), o
/// en modo debug en la web con `?ejemplo=nivel`. Una compilación normal no los
/// incluye: la constante queda vacía y el compilador descarta este camino.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _definido = String.fromEnvironment('DATOS_EJEMPLO');

const _niveles = {'normal', 'atencion', 'alerta', 'evacuacion', 'sindato'};

/// El nivel de ejemplo pedido, o null para usar los datos reales.
String? nivelDeEjemplo() {
  String? pedido;
  if (_definido.isNotEmpty) {
    pedido = _definido == 'url' ? Uri.base.queryParameters['ejemplo'] : _definido;
  } else if (kDebugMode && kIsWeb) {
    pedido = Uri.base.queryParameters['ejemplo'];
  }
  return _niveles.contains(pedido) ? pedido : null;
}

/// Un cliente HTTP que en vez de ir a internet responde los JSON de ejemplo.
http.Client clienteDeEjemplo(String nivel) {
  final ahora = DateTime.now().toUtc();
  final (valor, variacion, estado) = switch (nivel) {
    'normal' => (3.60, -0.03, 'baja'),
    'atencion' => (4.10, 0.05, 'crece'),
    'evacuacion' => (7.05, 0.04, 'crece'),
    _ => (5.83, 0.0, 'estacionado'),
  };
  // Sin dato: la última lectura es de hace 60 h (pasó el plazo para dar un nivel).
  final ultima = nivel == 'sindato' ? ahora.subtract(const Duration(hours: 60)) : ahora.subtract(const Duration(minutes: 20));
  String fecha(DateTime f) => f.toIso8601String();
  final grave = nivel == 'alerta' || nivel == 'evacuacion';
  final actual = {
    'generado': fecha(ahora),
    'cero': 'Local',
    'altura_actual': {
      'valor_m': valor,
      'fecha': fecha(ultima),
      'variacion_m': variacion,
      'periodo': '30 min',
      'estado': estado,
      'fuente': 'CARU – estación automática Paysandú',
      'url': 'http://190.0.152.194:8080/alturas/web/user/estacion/19/0',
    },
    'lectura_prefectura': {
      'valor_m': valor + 0.02,
      'fecha': fecha(ultima.subtract(const Duration(hours: 6))),
      'variacion_m': 0.1,
      'periodo': '24 hs',
      'estado': 'crece',
      'url': 'http://190.0.152.194:8080/alturas/web/user/altura/24',
    },
    'pronostico': {
      'vigente': grave,
      'informe_fecha': fecha(ahora).substring(0, 10),
      'altura_esperada_m': double.parse((valor + 0.09).toStringAsFixed(2)),
      'texto': 'El río continuará creciendo a niveles mayores los próximos días aguas abajo de la represa.',
      'caudal_salto_grande_m3s': 18000,
      'url_informe': 'https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf',
    },
    'nivel': nivel == 'sindato' ? 'alerta' : nivel,
    'avisos': <String>[],
  };
  const umbrales = {
    'validado': false,
    'cero': 'Local',
    'atencion_m': null,
    'alerta_m': 4.39,
    'evacuacion_m': 6.89,
    'actualizado': '2026-10-09',
  };
  // Una semana de lecturas cada hora: sube, hace un pico y baja hasta el valor de hoy.
  final historial = [
    for (var h = 7 * 24; h >= 0; h--)
      {
        'fecha': fecha(ultima.subtract(Duration(hours: h))),
        'valor_m': double.parse(
            (valor - 0.55 * (h / 168) + 0.35 * math.sin(math.pi * (1 - h / 168))).toStringAsFixed(2)),
        'fuente': 'estacion',
      },
  ];
  return MockClient((pedido) async => http.Response.bytes(
      utf8.encode(jsonEncode(switch (pedido.url.pathSegments.last) {
        'actual.json' => actual,
        'umbrales.json' => umbrales,
        _ => historial,
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'}));
}

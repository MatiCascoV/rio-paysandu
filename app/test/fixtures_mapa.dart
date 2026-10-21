/// Set chico y sintético de archivos del mapa (mismo formato que
/// docs/mapa/05-contrato.md), armado en memoria para las pruebas.
///
/// Capas de 4,00 a 4,30 m cada 10 cm, margen de 20 cm. La de 4,00 está vacía
/// (el agua no sale del cauce); las otras son rectángulos que crecen hacia el
/// este, anidados. Nada de esto es un dato real.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';

const _o = -58.10, _s = -32.40, _e = -58.00, _n = -32.30;

Uint8List _bytes(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, Object> baseDePrueba() => {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'t': 'agua'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [_o, _s],
                [-58.09, _s],
                [-58.09, _n],
                [_o, _n],
                [_o, _s],
              ]
            ],
          },
        },
        {
          'type': 'Feature',
          'properties': {'t': 'curso', 'n': 'Arroyo de Prueba'},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [-58.09, -32.35],
              [-58.05, -32.36],
            ],
          },
        },
        for (final (k, nombre, lat) in [(1, 'Ruta Uno', -32.32), (2, 'Avenida Dos', -32.34), (3, 'Calle Tres', -32.38)])
          {
            'type': 'Feature',
            'properties': {'t': 'calle', 'k': k, 'n': nombre},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [-58.09, lat],
                [-58.01, lat],
              ],
            },
          },
        {
          'type': 'Feature',
          'properties': {'t': 'calle', 'k': 3, 'n': null},
          'geometry': {
            'type': 'MultiLineString',
            'coordinates': [
              [
                [-58.05, -32.31],
                [-58.05, -32.39],
              ]
            ],
          },
        },
      ],
      'lugares': [
        {'n': 'Barrio Norte', 'c': [-58.06, -32.32]},
        {'n': 'Barrio Sur', 'c': [-58.06, -32.38]},
      ],
      'caja': [_o, _s, _e, _n],
    };

/// Capa de agua de [cm]: vacía en 400; si no, un rectángulo que llega más al
/// este cuanto más alta es la capa, con un hueco (zona alta seca).
Map<String, Object> capaDePrueba(int cm) {
  final este = -58.09 + (cm - 400) * 0.001;
  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'altura_m': cm / 100},
        'geometry': {
          'type': 'MultiPolygon',
          'coordinates': cm == 400
              ? []
              : [
                  [
                    [
                      [-58.09, -32.39],
                      [este, -32.39],
                      [este, -32.31],
                      [-58.09, -32.31],
                      [-58.09, -32.39],
                    ],
                    [
                      [-58.089, -32.36],
                      [-58.0885, -32.36],
                      [-58.0885, -32.355],
                      [-58.089, -32.36],
                    ],
                  ]
                ],
        },
      }
    ],
  };
}

const alturasDePrueba = [400, 410, 420, 430];

/// Archivos del set: indice.json, base.json y agua/NNNN.json.
///
/// [indice] permite cambiar el índice antes de serializarlo (para probar la
/// validación); [archivos] cambia o agrega archivos después de calcular las
/// huellas (para probar huellas que no coinciden).
Map<String, Uint8List> archivosDePrueba({
  void Function(Map<String, dynamic> indice)? indice,
  Map<String, Uint8List?> archivos = const {},
  String metodo = 'Prueba sintética',
}) {
  final salida = <String, Uint8List>{
    'base.json': _bytes(baseDePrueba()),
    for (final cm in alturasDePrueba) 'agua/${cm.toString().padLeft(4, '0')}.json': _bytes(capaDePrueba(cm)),
  };
  Map<String, Object> describir(String ruta) =>
      {'archivo': ruta, 'bytes': salida[ruta]!.length, 'sha256': sha256.convert(salida[ruta]!).toString()};
  final ind = <String, dynamic>{
    'version': 1,
    'generado': '2026-10-19T18:00:00-03:00',
    'cero': 'Local',
    'validado': false,
    'modelo': {'metodo': metodo, 'delta_m': 0.66, 'iou_validacion': 0.74, 'margen_m': 0.2},
    'limites': [
      [_s, _o],
      [_n, _e],
    ],
    'paso_m': 0.10,
    'min_m': 4.00,
    'max_m': 4.30,
    'base': describir('base.json'),
    'capas': [
      for (final cm in alturasDePrueba) {'altura_m': cm / 100, ...describir('agua/${cm.toString().padLeft(4, '0')}.json')},
    ],
    'referencias': [
      {'tipo': 'crecida', 'nombre': 'Crecida de prueba', 'altura_m': 4.25, 'fecha': '2015-12-10', 'fuente': 'Prueba'},
      {'tipo': 'crecida', 'nombre': 'Rota', 'altura_m': 'x'},
    ],
    'fuentes': ['Datos sintéticos de prueba'],
  };
  indice?.call(ind);
  salida['indice.json'] = _bytes(ind);
  archivos.forEach((ruta, b) => b == null ? salida.remove(ruta) : salida[ruta] = b);
  return salida;
}

FuenteMemoria fuenteDePrueba({
  void Function(Map<String, dynamic> indice)? indice,
  Map<String, Uint8List?> archivos = const {},
  String metodo = 'Prueba sintética',
}) =>
    FuenteMemoria(archivosDePrueba(indice: indice, archivos: archivos, metodo: metodo));

/// El índice del set, ya decodificado (para las pruebas de validación).
Map<String, dynamic> indiceDePrueba() =>
    jsonDecode(utf8.decode(archivosDePrueba()['indice.json']!)) as Map<String, dynamic>;

Uint8List jsonABytes(Object json) => _bytes(json);

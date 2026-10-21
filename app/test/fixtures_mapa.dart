/// Set sintético de archivos del mapa (mismo formato que
/// docs/mapa/05-contrato.md), armado en memoria para las pruebas.
///
/// Por defecto: capas de 4,00 a 4,30 m cada 10 cm, margen de 20 cm, una
/// crecida de referencia con su curva (curvas/2015-12.json) y `validado:
/// false`, como van a llegar los datos reales. Con [desde]/[hasta] se arma el
/// rango real del contrato (4,00 a 10,50 m, 66 capas). La capa de 4,00 está
/// vacía (el agua no sale del cauce); las otras son rectángulos que crecen
/// hacia el este, anidados. Nada de esto es un dato real.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';

const _o = -58.10, _s = -32.40, _e = -58.00, _n = -32.30;

Uint8List _bytes(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

String archivoCapa(int cm) => 'agua/${cm.toString().padLeft(4, '0')}.json';

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
          ],
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
          ],
        ],
      },
    },
  ],
  'lugares': [
    {
      'n': 'Barrio Norte',
      'c': [-58.06, -32.32],
    },
    {
      'n': 'Barrio Sur',
      'c': [-58.06, -32.38],
    },
  ],
  'caja': [_o, _s, _e, _n],
};

/// Capa de agua de [cm]: vacía en 400; si no, un rectángulo que llega más al
/// este cuanto más alta es la capa (1 cm de río = 0,0001° más), con un hueco
/// (zona alta seca). Hasta 10,50 m queda dentro de los límites.
Map<String, Object> capaDePrueba(int cm) {
  final este = -58.09 + (cm - 400) * 0.0001;
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
                      [-58.0899, -32.36],
                      [-58.0898, -32.36],
                      [-58.0898, -32.355],
                      [-58.0899, -32.36],
                    ],
                  ],
                ],
        },
      },
    ],
  };
}

/// Curva medida de una crecida (curvas/AAAA-MM.json), como la escribe el
/// pipeline: un Feature MultiPolygon con nombre, altura, fecha y fuente.
Map<String, Object> curvaDePrueba({String nombre = 'Crecida de prueba', double altura = 4.25}) => {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'properties': {'nombre': nombre, 'altura_m': altura, 'fecha': '2015-12-10', 'fuente': 'Dinagua'},
      'geometry': {
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [
              [-58.09, -32.385],
              [-58.06, -32.385],
              [-58.06, -32.315],
              [-58.09, -32.315],
              [-58.09, -32.385],
            ],
          ],
        ],
      },
    },
  ],
};

const alturasDePrueba = [400, 410, 420, 430];

/// Archivos del set: indice.json, base.json, agua/NNNN.json y curvas/.
///
/// [indice] permite cambiar el índice antes de serializarlo (para probar la
/// validación); [archivos] cambia o agrega archivos después de calcular las
/// huellas (para probar huellas que no coinciden).
Map<String, Uint8List> archivosDePrueba({
  void Function(Map<String, dynamic> indice)? indice,
  Map<String, Uint8List?> archivos = const {},
  String metodo = 'Prueba sintética',
  bool validado = false,
  int desde = 400,
  int hasta = 430,
}) {
  final alturas = [for (var cm = desde; cm <= hasta; cm += 10) cm];
  final salida = <String, Uint8List>{
    'base.json': _bytes(baseDePrueba()),
    for (final cm in alturas) archivoCapa(cm): _bytes(capaDePrueba(cm)),
    'curvas/2015-12.json': _bytes(curvaDePrueba()),
  };
  Map<String, Object> describir(String ruta) => {
    'archivo': ruta,
    'bytes': salida[ruta]!.length,
    'sha256': sha256.convert(salida[ruta]!).toString(),
  };
  final ind = <String, dynamic>{
    'version': 1,
    'generado': '2026-10-19T18:00:00-03:00',
    'cero': 'Local',
    'validado': validado,
    'modelo': {'metodo': metodo, 'delta_m': 0.66, 'iou_validacion': 0.74, 'margen_m': 0.2},
    'limites': [
      [_s, _o],
      [_n, _e],
    ],
    'paso_m': 0.10,
    'min_m': desde / 100,
    'max_m': hasta / 100,
    'base': describir('base.json'),
    'capas': [
      for (final cm in alturas) {'altura_m': cm / 100, ...describir(archivoCapa(cm))},
    ],
    'referencias': [
      {
        'tipo': 'crecida',
        'nombre': 'Crecida de prueba',
        'altura_m': 4.25,
        'fecha': '2015-12-10',
        ...describir('curvas/2015-12.json'),
        'fuente': 'Dinagua',
      },
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
  bool validado = false,
  int desde = 400,
  int hasta = 430,
}) => FuenteMemoria(
  archivosDePrueba(indice: indice, archivos: archivos, metodo: metodo, validado: validado, desde: desde, hasta: hasta),
);

/// El rango del contrato para los datos reales: 4,00 a 10,50 m (66 capas).
FuenteMemoria fuenteRangoReal({bool validado = false}) => fuenteDePrueba(desde: 400, hasta: 1050, validado: validado);

/// El índice del set, ya decodificado (para las pruebas de validación).
Map<String, dynamic> indiceDePrueba({int desde = 400, int hasta = 430}) =>
    jsonDecode(utf8.decode(archivosDePrueba(desde: desde, hasta: hasta)['indice.json']!)) as Map<String, dynamic>;

Uint8List jsonABytes(Object json) => _bytes(json);

/// De dónde salen los archivos del mapa. En la v1 vienen dentro del APK
/// (assets/mapa/); más adelante puede sumarse GitHub Pages con el mismo
/// formato sin tocar la pantalla (docs/mapa/05-contrato.md).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

abstract class FuenteMapa {
  const FuenteMapa();

  /// Bytes del archivo [ruta] (relativa a la carpeta del mapa, por ejemplo
  /// "agua/0670.json"), o null si no existe o pasa de [tope] bytes.
  Future<Uint8List?> leer(String ruta, {required int tope});
}

/// Archivos empaquetados en la app, en assets/mapa/.
class FuenteAssets extends FuenteMapa {
  final String carpeta;
  const FuenteAssets({this.carpeta = 'assets/mapa/'});

  @override
  Future<Uint8List?> leer(String ruta, {required int tope}) async {
    try {
      final datos = await rootBundle.load('$carpeta$ruta');
      if (datos.lengthInBytes > tope) return null;
      return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
    } catch (_) {
      return null; // el archivo no está en el APK
    }
  }
}

/// Archivos en memoria: para pruebas y para datos armados en el momento.
class FuenteMemoria extends FuenteMapa {
  final Map<String, Uint8List> archivos;

  /// Cuántas veces se leyó cada archivo (las pruebas miran la caché).
  final Map<String, int> lecturas = {};

  FuenteMemoria(this.archivos);

  @override
  Future<Uint8List?> leer(String ruta, {required int tope}) async {
    lecturas[ruta] = (lecturas[ruta] ?? 0) + 1;
    final b = archivos[ruta];
    return b == null || b.length > tope ? null : b;
  }
}

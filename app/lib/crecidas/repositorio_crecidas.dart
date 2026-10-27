/// Lee el índice, el fondo y los bordes de las crecidas desde una
/// [FuenteCrecidas], comprobando tamaño y huella (sha256) de cada archivo.
/// Cada archivo se lee una sola vez y queda en memoria (son pocos y chicos).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import 'modelos_crecidas.dart';

/// De dónde salen los archivos. Vienen dentro del APK (assets/crecidas/):
/// la pestaña funciona sin conexión desde la primera vez.
abstract class FuenteCrecidas {
  const FuenteCrecidas();

  /// Bytes del archivo [ruta] (relativa a la carpeta, por ejemplo
  /// "curvas/2019-01.json"), o null si no existe o pasa de [tope] bytes.
  Future<Uint8List?> leer(String ruta, {required int tope});
}

/// Archivos empaquetados en la app, en assets/crecidas/.
class FuenteAssets extends FuenteCrecidas {
  final String carpeta;
  const FuenteAssets({this.carpeta = 'assets/crecidas/'});

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

/// Archivos en memoria: para pruebas.
class FuenteMemoria extends FuenteCrecidas {
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

/// Resultado de cargar el índice.
sealed class EstadoIndice {
  const EstadoIndice();
}

class IndiceListo extends EstadoIndice {
  final IndiceCrecidas indice;
  const IndiceListo(this.indice);
}

/// No hay datos (faltan los archivos) o no pasaron la validación.
class IndiceNoDisponible extends EstadoIndice {
  final String motivo;
  const IndiceNoDisponible(this.motivo);
}

class RepositorioCrecidas {
  final FuenteCrecidas fuente;

  /// Con true, los archivos grandes (el fondo) se decodifican en otro hilo
  /// para no trabar la pantalla. En las pruebas va en false.
  final bool enSegundoPlano;

  RepositorioCrecidas(this.fuente, {this.enSegundoPlano = false});

  /// A partir de este tamaño se decodifica en otro hilo.
  static const _bytesParaSegundoPlano = 96 * 1024;

  Future<EstadoIndice>? _indice;
  Future<BaseMapa?>? _base;
  final _bordes = <String, Future<BordeCrecida?>>{};

  Future<EstadoIndice> indice() => _indice ??= _cargarIndice();

  Future<EstadoIndice> _cargarIndice() async {
    final bytes = await fuente.leer('indice.json', tope: TopesCrecidas.bytesIndice);
    if (bytes == null) return const IndiceNoDisponible('no hay indice.json');
    try {
      return IndiceListo(IndiceCrecidas.desdeJson(jsonDecode(utf8.decode(bytes))));
    } on ErrorCrecidas catch (e) {
      return IndiceNoDisponible(e.motivo);
    } catch (_) {
      return const IndiceNoDisponible('indice.json no es JSON válido');
    }
  }

  /// Lee [a] y lo arma con [armar] si existe, pesa lo que dice el índice y su
  /// huella coincide; si no, null.
  Future<T?> _leerYArmar<T, A>(ArchivoCrecidas a, int tope, T Function(Object?, A) armar, A extra) async {
    final bytes = await fuente.leer(a.archivo, tope: tope);
    if (bytes == null || bytes.length != a.bytes) return null;
    final pedido = _Pedido<T, A>(bytes, a.sha256, armar, extra);
    try {
      if (enSegundoPlano && bytes.length >= _bytesParaSegundoPlano) {
        return await compute(_verificarYArmar<T, A>, pedido, debugLabel: 'crecidas ${a.archivo}');
      }
      return _verificarYArmar(pedido);
    } catch (_) {
      return null; // JSON roto o que no valida: se trata como si faltara
    }
  }

  /// El fondo, o null si falta o no valida.
  Future<BaseMapa?> base() => _base ??= () async {
    final e = await indice();
    if (e is! IndiceListo) return null;
    return _leerYArmar(e.indice.base, TopesCrecidas.bytesBase, _armarBase, e.indice);
  }();

  /// El borde de [crecida], o null si el archivo falta o no valida.
  Future<BordeCrecida?> borde(Crecida crecida) => _bordes[crecida.clave] ??= () async {
    final e = await indice();
    if (e is! IndiceListo) return null;
    return _leerYArmar(crecida.archivo, TopesCrecidas.bytesBorde, _armarBorde, (crecida, e.indice));
  }();
}

/// Lo que viaja al otro hilo: bytes, textos, objetos del índice y funciones
/// de nivel superior.
class _Pedido<T, A> {
  final Uint8List bytes;
  final String sha256;
  final T Function(Object?, A) armar;
  final A extra;
  const _Pedido(this.bytes, this.sha256, this.armar, this.extra);
}

T? _verificarYArmar<T, A>(_Pedido<T, A> p) {
  if (crypto.sha256.convert(p.bytes).toString() != p.sha256) return null;
  return p.armar(jsonDecode(utf8.decode(p.bytes)), p.extra);
}

BaseMapa _armarBase(Object? j, IndiceCrecidas ind) => BaseMapa.desdeJson(j, ind);
BordeCrecida _armarBorde(Object? j, (Crecida, IndiceCrecidas) e) => BordeCrecida.desdeJson(j, e.$1, e.$2);

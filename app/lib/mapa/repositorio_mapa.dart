/// Lee el índice, el fondo y las capas de agua desde una [FuenteMapa],
/// comprobando tamaño y huella de cada archivo, y guarda en memoria las
/// últimas capas usadas para que el deslizador no vuelva a leerlas.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;

import 'fuente_mapa.dart';
import 'modelos_mapa.dart';

/// Resultado de cargar el índice.
sealed class EstadoIndice {
  const EstadoIndice();
}

class IndiceListo extends EstadoIndice {
  final IndiceMapa indice;
  const IndiceListo(this.indice);
}

/// No hay mapa (faltan los archivos) o no pasó la validación.
class IndiceNoDisponible extends EstadoIndice {
  final String motivo;
  const IndiceNoDisponible(this.motivo);
}

/// Una capa leída y la altura que de verdad representa: si la pedida no se
/// pudo leer se usa la siguiente hacia arriba (nunca hacia abajo).
class CapaElegida {
  final CapaAgua capa;
  final int pedidaCm;
  int get alturaCm => capa.alturaCm;
  bool get reemplazada => capa.alturaCm != pedidaCm;
  const CapaElegida(this.capa, this.pedidaCm);
}

class RepositorioMapa {
  final FuenteMapa fuente;

  /// Con true, los archivos grandes se decodifican en otro hilo (compute)
  /// para no trabar la pantalla. En las pruebas va en false: todo en el
  /// mismo hilo, sin esperas reales.
  final bool enSegundoPlano;

  /// Capas decodificadas que se guardan en memoria (las más recientes).
  final int capasEnMemoria;

  RepositorioMapa(this.fuente, {this.enSegundoPlano = false, this.capasEnMemoria = 12});

  Future<EstadoIndice>? _indice;
  Future<BaseMapa?>? _base;
  final _capas = <int, CapaAgua>{}; // guarda el orden de uso
  final _rotas = <int>{};

  /// A partir de este tamaño se decodifica en otro hilo.
  static const _bytesParaSegundoPlano = 96 * 1024;

  Future<EstadoIndice> indice() => _indice ??= _cargarIndice();

  Future<EstadoIndice> _cargarIndice() async {
    final bytes = await fuente.leer('indice.json', tope: TopesMapa.bytesIndice);
    if (bytes == null) return const IndiceNoDisponible('no hay indice.json');
    try {
      return IndiceListo(IndiceMapa.desdeJson(jsonDecode(utf8.decode(bytes))));
    } on ErrorMapa catch (e) {
      return IndiceNoDisponible(e.motivo);
    } catch (_) {
      return const IndiceNoDisponible('indice.json no es JSON válido');
    }
  }

  /// Lee [a] y lo arma con [armar] si existe, pesa lo que dice el índice y su
  /// huella coincide; si no, null. La huella, el JSON y el armado de los
  /// objetos van juntos: con [enSegundoPlano] y un archivo grande, todo eso
  /// pasa en otro hilo y la pantalla no se traba.
  Future<T?> _leerYArmar<T, A>(ArchivoMapa a, int tope, T Function(Object?, A) armar, A extra) async {
    final bytes = await fuente.leer(a.archivo, tope: tope);
    if (bytes == null || bytes.length != a.bytes) return null;
    final pedido = _Pedido<T, A>(bytes, a.sha256, armar, extra);
    try {
      if (enSegundoPlano && bytes.length >= _bytesParaSegundoPlano) {
        return await compute(_verificarYArmar<T, A>, pedido, debugLabel: 'mapa ${a.archivo}');
      }
      return _verificarYArmar(pedido);
    } catch (_) {
      return null; // JSON roto o que no valida: se trata como si faltara
    }
  }

  /// El fondo, o null si falta o no valida.
  Future<BaseMapa?> base() => _base ??= _cargarBase();

  Future<BaseMapa?> _cargarBase() async {
    final e = await indice();
    if (e is! IndiceListo) return null;
    final ind = e.indice;
    return _leerYArmar(ind.base, TopesMapa.bytesBase, _armarBase, ind);
  }

  /// La capa de [cm] (múltiplo del paso, dentro del rango). Si esa no se
  /// puede leer, la siguiente hacia arriba; null si no queda ninguna.
  Future<CapaElegida?> capa(int cm) async {
    final e = await indice();
    if (e is! IndiceListo) return null;
    final ind = e.indice;
    for (var c = cm; c <= ind.maxCm; c += ind.pasoCm) {
      final capa = await _capa(ind, c);
      if (capa != null) return CapaElegida(capa, cm);
    }
    return null;
  }

  Future<CapaAgua?> _capa(IndiceMapa ind, int cm) async {
    final enMemoria = _capas.remove(cm);
    if (enMemoria != null) return _capas[cm] = enMemoria; // queda como la más reciente
    if (_rotas.contains(cm)) return null;
    final c = ind.capaDe(cm);
    if (c == null) return null;
    final capa = await _leerYArmar(c, TopesMapa.bytesCapa, _armarCapa, (c, ind));
    if (capa == null) {
      _rotas.add(cm); // no se vuelve a intentar en esta sesión
      return null;
    }
    _capas[cm] = capa;
    while (_capas.length > capasEnMemoria) {
      _capas.remove(_capas.keys.first);
    }
    return capa;
  }

  /// Alturas de las capas que hay en memoria, de la más vieja a la más nueva.
  List<int> get capasGuardadas => List.unmodifiable(_capas.keys);

  final _curvas = <String, Future<CurvaMapa?>>{};

  /// Contorno medido de una crecida real (curvas/…), o null si la referencia
  /// no trae archivo o el archivo no valida. Se guarda una vez leído.
  Future<CurvaMapa?> curva(ReferenciaMapa ref) {
    final a = ref.archivo;
    if (a == null) return Future.value(null);
    return _curvas[a.archivo] ??= () async {
      final e = await indice();
      if (e is! IndiceListo) return null;
      return _leerYArmar(a, TopesMapa.bytesCurva, _armarCurva, (ref, e.indice));
    }();
  }
}

/// Lo que viaja al otro hilo. Todo es enviable: bytes, textos, objetos del
/// índice y funciones de nivel superior (no clausuras con estado).
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

BaseMapa _armarBase(Object? j, IndiceMapa ind) => BaseMapa.desdeJson(j, ind);
CapaAgua _armarCapa(Object? j, (CapaIndice, IndiceMapa) e) => CapaAgua.desdeJson(j, e.$1, e.$2);
CurvaMapa _armarCurva(Object? j, (ReferenciaMapa, IndiceMapa) e) => CurvaMapa.desdeJson(j, e.$1, e.$2);

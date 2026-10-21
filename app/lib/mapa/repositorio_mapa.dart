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

  RepositorioMapa(this.fuente, {this.enSegundoPlano = false, this.capasEnMemoria = 20});

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

  /// Bytes de [a] si existen, pesan lo que dice el índice y su huella coincide.
  Future<Uint8List?> _leerVerificado(ArchivoMapa a, int tope) async {
    final bytes = await fuente.leer(a.archivo, tope: tope);
    if (bytes == null || bytes.length != a.bytes) return null;
    if (crypto.sha256.convert(bytes).toString() != a.sha256) return null;
    return bytes;
  }

  Future<T> _decodificar<T>(Uint8List bytes, T Function(Object?) armar) async {
    if (enSegundoPlano && bytes.length >= _bytesParaSegundoPlano) {
      return compute(_decodificarYArmar<T>, (bytes, armar));
    }
    return armar(jsonDecode(utf8.decode(bytes)));
  }

  /// El fondo, o null si falta o no valida.
  Future<BaseMapa?> base() => _base ??= _cargarBase();

  Future<BaseMapa?> _cargarBase() async {
    final e = await indice();
    if (e is! IndiceListo) return null;
    final ind = e.indice;
    final bytes = await _leerVerificado(ind.base, TopesMapa.bytesBase);
    if (bytes == null) return null;
    try {
      return await _decodificar(bytes, (j) => BaseMapa.desdeJson(j, ind));
    } catch (_) {
      return null;
    }
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
    final bytes = await _leerVerificado(c, TopesMapa.bytesCapa);
    CapaAgua? capa;
    if (bytes != null) {
      try {
        capa = await _decodificar(bytes, (j) => CapaAgua.desdeJson(j, c, ind));
      } catch (_) {}
    }
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
}

T _decodificarYArmar<T>((Uint8List, T Function(Object?)) e) => e.$2(jsonDecode(utf8.decode(e.$1)));

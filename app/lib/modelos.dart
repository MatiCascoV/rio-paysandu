/// Modelos de los JSON que publica el lector (ver sección 5 de PROMPT_MAESTRO.md).
/// La lectura es tolerante: si falta un campo queda en null, nunca se inventa.
library;

import 'enlaces.dart';

// Inicio decide con esto si muestra el botón del enlace.
export 'enlaces.dart' show enlacePermitido;

enum Nivel { normal, atencion, alerta, evacuacion, sinDato }

Nivel nivelDesdeTexto(String? texto) => switch (texto) {
      'normal' => Nivel.normal,
      'atencion' => Nivel.atencion,
      'alerta' => Nivel.alerta,
      'evacuacion' => Nivel.evacuacion,
      _ => Nivel.sinDato,
    };

String nivelATexto(Nivel n) => switch (n) {
      Nivel.normal => 'normal',
      Nivel.atencion => 'atencion',
      Nivel.alerta => 'alerta',
      Nivel.evacuacion => 'evacuacion',
      Nivel.sinDato => 'sin_dato',
    };

/// Solo números de verdad: nada de infinito ni NaN.
double? _numero(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _texto(Object? v) => v is String ? v : null;

/// Altura o umbral en metros: fuera de 0 a 20 m es un error, no un dato.
double? _altura(Object? v) {
  final n = _numero(v);
  return n != null && n >= 0 && n <= 20 ? n : null;
}

/// Variación de altura: como mucho lo que mide la escala, para arriba o abajo.
double? _variacion(Object? v) {
  final n = _numero(v);
  return n != null && n.abs() <= 20 ? n : null;
}

/// Enlace a CARU: solo si es de un sitio permitido (ver enlaces.dart).
String? _enlace(Object? v) {
  final t = _texto(v);
  return enlacePermitido(t) ? t : null;
}

/// Tope del caudal: el río Uruguay nunca pasó de unos 40.000 m³/s.
const _caudalMaximo = 200000;

/// Tope del texto del pronóstico, para que un texto raro no ocupe la pantalla.
const largoMaximoTexto = 600;

String? _textoCorto(Object? v) {
  final t = _texto(v);
  if (t == null || t.runes.length <= largoMaximoTexto) return t;
  return '${String.fromCharCodes(t.runes.take(largoMaximoTexto - 1))}…';
}

/// Una lectura más de 1 h posterior a `generado` (del mismo JSON) es un error.
/// Se compara contra `generado` y no contra el reloj del teléfono: un teléfono
/// atrasado no puede quedarse sin nivel ni sin avisos.
const _margenFuturo = Duration(hours: 1);

bool _posteriorA(DateTime fecha, DateTime? generado) =>
    generado != null && fecha.difference(generado) > _margenFuturo;

class Lectura {
  final double valorM;
  final DateTime fecha;
  final double? variacionM;
  final String? periodo;
  final String? estado;
  final String? fuente;
  final String? url;

  const Lectura({
    required this.valorM,
    required this.fecha,
    this.variacionM,
    this.periodo,
    this.estado,
    this.fuente,
    this.url,
  });

  static Lectura? desdeJson(Object? j) {
    if (j is! Map) return null;
    final valor = _altura(j['valor_m']);
    final fecha = _fecha(j['fecha']);
    if (valor == null || fecha == null) return null;
    return Lectura(
      valorM: valor,
      fecha: fecha,
      variacionM: _variacion(j['variacion_m']),
      periodo: _texto(j['periodo']),
      estado: _texto(j['estado']),
      fuente: _texto(j['fuente']),
      url: _enlace(j['url']),
    );
  }
}

class Pronostico {
  final bool vigente;
  final DateTime? informeFecha;
  final double? alturaEsperadaM;
  final String? texto;
  final int? caudalM3s;
  final String? urlInforme;

  const Pronostico({
    required this.vigente,
    this.informeFecha,
    this.alturaEsperadaM,
    this.texto,
    this.caudalM3s,
    this.urlInforme,
  });

  static Pronostico? desdeJson(Object? j) {
    if (j is! Map) return null;
    return Pronostico(
      vigente: j['vigente'] == true,
      informeFecha: _fecha(j['informe_fecha']),
      alturaEsperadaM: _altura(j['altura_esperada_m']),
      texto: _textoCorto(j['texto']),
      caudalM3s: _caudal(j['caudal_salto_grande_m3s']),
      urlInforme: _enlace(j['url_informe']),
    );
  }
}

int? _caudal(Object? v) {
  final n = _numero(v);
  return n != null && n >= 0 && n <= _caudalMaximo ? n.round() : null;
}

class Actual {
  final Lectura? altura;
  final Lectura? prefectura;
  final Pronostico? pronostico;
  final Nivel nivel;
  final List<String> avisos;
  final String? cero;

  /// Cuándo armó el lector este contenido.
  final DateTime? generado;

  const Actual({
    this.altura,
    this.prefectura,
    this.pronostico,
    this.nivel = Nivel.sinDato,
    this.avisos = const [],
    this.cero,
    this.generado,
  });

  static Actual? desdeJson(Object? j) {
    if (j is! Map) return null;
    final avisos = j['avisos'];
    return Actual(
      altura: Lectura.desdeJson(j['altura_actual']),
      prefectura: Lectura.desdeJson(j['lectura_prefectura']),
      pronostico: Pronostico.desdeJson(j['pronostico']),
      nivel: nivelDesdeTexto(_texto(j['nivel'])),
      avisos: avisos is List ? avisos.whereType<String>().toList() : const [],
      cero: _texto(j['cero']),
      generado: _fecha(j['generado']),
    );
  }

  /// Nivel que la app puede mostrar: si no hay altura, o es demasiado vieja
  /// (por ejemplo porque el lector dejó de correr), es "sin dato". Una lectura
  /// posterior a cuando se armó el JSON también: el dato está mal.
  Nivel nivelVigente(DateTime ahora, int horasSinDato) {
    final a = altura;
    if (a == null) return Nivel.sinDato;
    if (_posteriorA(a.fecha, generado)) return Nivel.sinDato;
    if (ahora.difference(a.fecha).inMinutes > horasSinDato * 60) return Nivel.sinDato;
    return nivel;
  }
}

class Umbrales {
  final bool validado;
  final double? atencionM;
  final double? alertaM;
  final double? evacuacionM;

  const Umbrales({this.validado = false, this.atencionM, this.alertaM, this.evacuacionM});

  static Umbrales? desdeJson(Object? j) {
    if (j is! Map) return null;
    return Umbrales(
      validado: j['validado'] == true,
      atencionM: _altura(j['atencion_m']),
      alertaM: _altura(j['alerta_m']),
      evacuacionM: _altura(j['evacuacion_m']),
    );
  }

  double? de(Nivel n) => switch (n) {
        Nivel.atencion => atencionM,
        Nivel.alerta => alertaM,
        Nivel.evacuacion => evacuacionM,
        _ => null,
      };
}

class PuntoHistorial {
  final DateTime fecha;
  final double valorM;
  final String fuente; // "estacion" o "prefectura"

  const PuntoHistorial(this.fecha, this.valorM, this.fuente);

  /// Se descartan los puntos sin fecha, con alturas imposibles o posteriores
  /// en más de 1 h a [generado] (el de actual.json; sin él no se descarta por fecha).
  static List<PuntoHistorial> listaDesdeJson(Object? j, {DateTime? generado}) {
    if (j is! List) return const [];
    final puntos = <PuntoHistorial>[];
    for (final e in j) {
      if (e is! Map) continue;
      final fecha = _fecha(e['fecha']);
      final valor = _altura(e['valor_m']);
      if (fecha != null && valor != null && !_posteriorA(fecha, generado)) {
        puntos.add(PuntoHistorial(fecha, valor, _texto(e['fuente']) ?? ''));
      }
    }
    puntos.sort((a, b) => a.fecha.compareTo(b.fecha));
    return puntos;
  }
}

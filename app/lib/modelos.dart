/// Modelos de los JSON que publica el lector (ver sección 5 de PROMPT_MAESTRO.md).
/// La lectura es tolerante: si falta un campo queda en null, nunca se inventa.
library;

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

double? _numero(Object? v) => v is num ? v.toDouble() : null;
DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _texto(Object? v) => v is String ? v : null;

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
    final valor = _numero(j['valor_m']);
    final fecha = _fecha(j['fecha']);
    if (valor == null || fecha == null) return null;
    return Lectura(
      valorM: valor,
      fecha: fecha,
      variacionM: _numero(j['variacion_m']),
      periodo: _texto(j['periodo']),
      estado: _texto(j['estado']),
      fuente: _texto(j['fuente']),
      url: _texto(j['url']),
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
      alturaEsperadaM: _numero(j['altura_esperada_m']),
      texto: _texto(j['texto']),
      caudalM3s: _numero(j['caudal_salto_grande_m3s'])?.round(),
      urlInforme: _texto(j['url_informe']),
    );
  }
}

class Actual {
  final Lectura? altura;
  final Lectura? prefectura;
  final Pronostico? pronostico;
  final Nivel nivel;
  final List<String> avisos;
  final String? cero;

  const Actual({
    this.altura,
    this.prefectura,
    this.pronostico,
    this.nivel = Nivel.sinDato,
    this.avisos = const [],
    this.cero,
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
    );
  }

  /// Nivel que la app puede mostrar: si no hay altura, o es demasiado vieja
  /// (por ejemplo porque el lector dejó de correr), es "sin dato".
  Nivel nivelVigente(DateTime ahora, int horasSinDato) {
    final a = altura;
    if (a == null) return Nivel.sinDato;
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
      atencionM: _numero(j['atencion_m']),
      alertaM: _numero(j['alerta_m']),
      evacuacionM: _numero(j['evacuacion_m']),
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

  static List<PuntoHistorial> listaDesdeJson(Object? j) {
    if (j is! List) return const [];
    final puntos = <PuntoHistorial>[];
    for (final e in j) {
      if (e is! Map) continue;
      final fecha = _fecha(e['fecha']);
      final valor = _numero(e['valor_m']);
      if (fecha != null && valor != null) {
        puntos.add(PuntoHistorial(fecha, valor, _texto(e['fuente']) ?? ''));
      }
    }
    puntos.sort((a, b) => a.fecha.compareTo(b.fecha));
    return puntos;
  }
}

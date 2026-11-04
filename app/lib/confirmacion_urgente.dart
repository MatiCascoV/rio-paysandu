/// M-1 en el teléfono: el aviso urgente espera una segunda lectura que lo
/// confirme, con la misma regla que `lector/avisos.py` (el servidor).
///
/// El servidor decide con todo el historial de actual.json; el teléfono solo ve
/// las publicaciones que baja en cada revisión (la app abierta, el push o el
/// respaldo de workmanager, que puede pasar horas sin correr). Por eso acá la
/// regla va "en marcha": se guarda por nivel urgente la primera lectura de la
/// subida (la candidata) y si ya se avisó, y cada publicación nueva la confirma,
/// la deja en espera o la descarta.
///
/// Regla (la de `_confirma` y `_evento_en` de avisos.py):
/// - La subida a un nivel empieza con la primera publicación vista con ese
///   nivel o más, después de una con nivel menor. Esa primera no avisa.
/// - Avisa la primera publicación posterior DE ESE NIVEL que la confirma (fecha de
///   lectura mayor, misma fuente, salto de hasta 1 m), o la primera de ese nivel
///   con `generado` 60 min o más después de la candidata (tope: nunca callar).
/// - `dato_a_verificar` solo no frena (en el teléfono las alturas siempre se
///   pueden comparar: sin altura no hay nivel).
/// - Si la publicación vista antes retenía este mismo nivel (`nivel_retenido`),
///   el lector ya esperó una segunda lectura: avisa de una.
/// - Cada nivel avisa una vez por subida; si avisa evacuación, la alerta de esa
///   misma subida ya no avisa. Bajar del nivel reinicia la espera.
/// - Sin nivel anterior conocido no se avisa (como el servidor).
///
/// Lo propio del teléfono (el servidor no lo necesita):
/// - Revisión espaciada: si entre la publicación vista antes y esta pasaron más de
///   60 min y esta lectura contradice a la candidata (salto de más de 1 m, otra
///   fuente o una fecha anterior), no se avisa por tope: el teléfono no vio lo del
///   medio. Esta pasa a ser la candidata nueva y se espera otra lectura.
/// - Push: el servidor ya confirmó. Un push urgente de un nivel avisa de una si el
///   dato muestra ese nivel o más; si el dato todavía no lo muestra, queda
///   anotado y lo usa la próxima revisión que sí lo muestre.
///
/// El tiempo se mide siempre con `generado` de las publicaciones, nunca con el
/// reloj del teléfono (puede estar mal).
///
/// Sin plugins: todo se prueba sin teléfono.
library;

import 'modelos.dart';

/// Tope de espera de la segunda lectura (`VENTANA_CONFIRMACION` de avisos.py).
const ventanaConfirmacion = Duration(minutes: 60);

/// Salto máximo (m) entre la candidata y la lectura que la confirma (`SALTO_MAX_M`).
const saltoMaxConfirmacionM = 1.0;

const nivelesUrgentes = [Nivel.alerta, Nivel.evacuacion];

/// Lo que hace falta de una publicación para confirmar una subida.
class LecturaM1 {
  /// `generado` de la publicación; null si no vino (entonces no se puede medir
  /// el tope y, como el servidor, se prefiere avisar a callar).
  final DateTime? generado;

  /// Fecha de la lectura de altura (`altura_actual.fecha`).
  final DateTime fecha;
  final double valorM;
  final String? fuente;

  const LecturaM1({required this.generado, required this.fecha, required this.valorM, this.fuente});

  /// La lectura de [actual], o null si no tiene altura.
  static LecturaM1? de(Actual actual) {
    final a = actual.altura;
    if (a == null) return null;
    return LecturaM1(generado: actual.generado, fecha: a.fecha, valorM: a.valorM, fuente: a.fuente);
  }

  Map<String, Object?> aJson() => {
        'generado': generado?.toUtc().toIso8601String(),
        'fecha': fecha.toUtc().toIso8601String(),
        'valor_m': valorM,
        'fuente': fuente,
      };

  static LecturaM1? desdeJson(Object? j) {
    if (j is! Map) return null;
    final fecha = j['fecha'] is String ? DateTime.tryParse(j['fecha'] as String) : null;
    final valor = j['valor_m'];
    if (fecha == null || valor is! num || !valor.isFinite) return null;
    final generado = j['generado'] is String ? DateTime.tryParse(j['generado'] as String) : null;
    final fuente = j['fuente'];
    return LecturaM1(generado: generado, fecha: fecha, valorM: valor.toDouble(), fuente: fuente is String ? fuente : null);
  }
}

/// ¿[otra] confirma a [primera]? Fecha posterior, misma fuente y salto de hasta
/// 1 m (`_confirma` de avisos.py, con la misma cuenta en coma flotante).
bool confirmaLectura(LecturaM1 primera, LecturaM1 otra) =>
    otra.fecha.isAfter(primera.fecha) &&
    primera.fuente == otra.fuente &&
    (otra.valorM - primera.valorM).abs() <= saltoMaxConfirmacionM;

/// ¿[otra] contradice a [primera]? Salto de más de 1 m, otra fuente o una fecha
/// anterior. La misma fecha (la estación no informó nada nuevo) no contradice.
bool contradiceLectura(LecturaM1 primera, LecturaM1 otra) =>
    otra.fecha.isBefore(primera.fecha) ||
    primera.fuente != otra.fuente ||
    (otra.valorM - primera.valorM).abs() > saltoMaxConfirmacionM;

/// La subida en curso a un nivel urgente.
class RachaM1 {
  /// Primera lectura de la subida (la candidata). Puede faltar si [avisado].
  final LecturaM1? inicio;

  /// El urgente de este nivel ya salió (o no corresponde) en esta subida.
  final bool avisado;

  const RachaM1(this.inicio, {required this.avisado});

  RachaM1 yaAvisada() => RachaM1(inicio, avisado: true);

  Map<String, Object?> aJson() => {'inicio': inicio?.aJson(), 'avisado': avisado};

  static RachaM1? desdeJson(Object? j) {
    if (j is! Map) return null;
    final inicio = LecturaM1.desdeJson(j['inicio']);
    final avisado = j['avisado'] == true || inicio == null; // sin candidata no hay nada que esperar
    return RachaM1(inicio, avisado: avisado);
  }
}

/// Un push urgente que llegó antes de que el dato mostrara la subida.
class PushPendiente {
  final Nivel nivel;

  /// Hora de envío de FCM (o, sin ella, cuando llegó).
  final DateTime enviado;

  const PushPendiente(this.nivel, this.enviado);
}

/// Lo guardado entre revisiones (además de `ultimo_nivel` y `ultimo_nivel_generado`).
class EstadoM1 {
  final Map<Nivel, RachaM1> rachas;

  /// `nivel_retenido.nivel` de la última publicación con dato vista.
  final Nivel? retenido;
  final PushPendiente? push;

  const EstadoM1({this.rachas = const {}, this.retenido, this.push});

  Map<String, Object?> aJson() => {
        for (final n in nivelesUrgentes) nivelATexto(n): rachas[n]?.aJson(),
        'retenido': retenido == null ? null : nivelATexto(retenido!),
        'push': push == null
            ? null
            : {'nivel': nivelATexto(push!.nivel), 'enviado': push!.enviado.toUtc().toIso8601String()},
      };

  /// Lectura tolerante: lo que venga mal queda vacío (ver [pasoM1] para qué
  /// pasa con una racha que falta).
  static EstadoM1 desdeJson(Object? j) {
    if (j is! Map) return const EstadoM1();
    Nivel? urgente(Object? t) {
      final n = nivelDesdeTexto(t is String ? t : null);
      return nivelesUrgentes.contains(n) ? n : null;
    }

    PushPendiente? push;
    final p = j['push'];
    if (p is Map) {
      final nivel = urgente(p['nivel']);
      final enviado = p['enviado'] is String ? DateTime.tryParse(p['enviado'] as String) : null;
      if (nivel != null && enviado != null) push = PushPendiente(nivel, enviado);
    }
    final retenido = nivelDesdeTexto(j['retenido'] is String ? j['retenido'] as String : null);
    return EstadoM1(
      rachas: {
        for (final n in nivelesUrgentes) n: ?RachaM1.desdeJson(j[nivelATexto(n)]),
      },
      retenido: retenido == Nivel.sinDato ? null : retenido,
      push: push,
    );
  }
}

/// Resultado de mirar una publicación.
class PasoM1 {
  final EstadoM1 estado;

  /// Nivel del urgente que sale con esta publicación (el más alto, si salen dos), o null.
  final Nivel? sale;

  /// "confirmada", "plazo", "retencion", "push", "espera" (hay una subida
  /// esperando la segunda lectura) o "" (nada que esperar).
  final String como;

  const PasoM1(this.estado, this.sale, this.como);
}

int _rango(Nivel n) => ordenDeNivel(n);

/// Mira una publicación con dato y decide si sale el urgente.
///
/// - [anterior]: último nivel con dato visto antes (null si nunca vio uno).
/// - [vistoAntes]: `generado` de esa publicación.
/// - [nivel]: el nivel de esta publicación (no `sinDato`) y [lectura], su lectura.
/// - [push]: nivel de un push urgente que se está atendiendo ahora, enviado a la
///   hora [enviado] ([ahora] si no se sabe).
///
/// No mira preferencias: la subida avanza igual con el urgente apagado (como el
/// servidor, que avisa aunque nadie esté suscrito), y quien llama decide si la muestra.
PasoM1 pasoM1(
  EstadoM1 previo, {
  required Nivel? anterior,
  required DateTime? vistoAntes,
  required Nivel nivel,
  required LecturaM1 lectura,
  required Nivel? retenidoAhora,
  Nivel? push,
  DateTime? enviado,
  required DateTime ahora,
}) {
  assert(nivel != Nivel.sinDato);
  final rachas = <Nivel, RachaM1>{};
  final eventos = <Nivel, String>{};

  for (final x in nivelesUrgentes) {
    if (_rango(nivel) < _rango(x)) continue; // bajó de x (o nunca llegó): la subida termina
    final previa = previo.rachas[x];
    final sigue = anterior != null && _rango(anterior) >= _rango(x);
    if (!sigue) {
      // Empieza una subida a x (o más) con esta publicación: es la candidata.
      // Sin nivel anterior conocido no se avisa (como el servidor).
      rachas[x] = RachaM1(lectura, avisado: anterior == null);
      if (anterior != null && x == nivel && previo.retenido == x) eventos[x] = 'retencion';
      continue;
    }
    if (previa == null) {
      // Ya estaba en x o más y no hay racha guardada: viene de la versión anterior de
      // la app (que avisaba con la primera lectura) o se perdió lo guardado. Se da por
      // avisada: repetir un urgente es peor.
      rachas[x] = RachaM1(lectura, avisado: true);
      continue;
    }
    rachas[x] = previa;
    // Solo una publicación DE ESE NIVEL confirma o vence el tope (avisos.py, _evento_en).
    if (previa.avisado || x != nivel) continue;
    final inicio = previa.inicio!;
    if (confirmaLectura(inicio, lectura)) {
      eventos[x] = 'confirmada';
      continue;
    }
    final g0 = inicio.generado;
    final g = lectura.generado;
    // Si no se puede medir el tiempo se prefiere avisar a callar (como el servidor).
    final vencido = g0 == null || g == null || g.difference(g0) >= ventanaConfirmacion;
    if (!vencido) continue;
    final hueco = (vistoAntes == null || g == null) ? Duration.zero : g.difference(vistoAntes);
    if (hueco > ventanaConfirmacion && contradiceLectura(inicio, lectura)) {
      // El teléfono no vio lo del medio y esta lectura no cuadra con la candidata:
      // no se avisa por tope con una lectura vieja. Esta es la candidata nueva.
      rachas[x] = RachaM1(lectura, avisado: false);
      continue;
    }
    eventos[x] = 'plazo';
  }

  // Push: el servidor ya vio la segunda lectura. El de ahora o uno anotado antes.
  var pendiente = previo.push;
  if (push != null) pendiente = PushPendiente(push, enviado ?? ahora);
  if (pendiente != null) {
    if (_rango(nivel) >= _rango(pendiente.nivel)) {
      if (!rachas[pendiente.nivel]!.avisado) eventos.putIfAbsent(pendiente.nivel, () => 'push');
      pendiente = null; // usado (o ya se había avisado por otra puerta)
    } else if (lectura.generado != null && lectura.generado!.isAfter(pendiente.enviado)) {
      pendiente = null; // un dato posterior al envío ya no muestra la subida: el río bajó
    }
    // Si no, el dato todavía es anterior al push: queda anotado para la próxima revisión.
  }

  Nivel? sale;
  for (final e in eventos.keys) {
    if (sale == null || _rango(e) > _rango(sale)) sale = e;
    // Avisó e: esa subida y las de los niveles de abajo ya no avisan.
    for (final x in nivelesUrgentes) {
      if (_rango(x) <= _rango(e) && rachas[x] != null) rachas[x] = rachas[x]!.yaAvisada();
    }
  }
  final como = sale != null
      ? eventos[sale]!
      : (rachas[nivel]?.avisado == false ? 'espera' : '');
  return PasoM1(EstadoM1(rachas: rachas, retenido: retenidoAhora, push: pendiente), sale, como);
}

/// M-1 en el respaldo local: el urgente espera una segunda lectura, con la misma
/// regla que lector/avisos.py. Primero la regla sola ([pasoM1]), después por
/// [decidirAvisos] (preferencias, push, marcas) y al final los casos que decidió
/// el servidor (test/fixtures/casos_m1_servidor.json, de lector/tests/casos_m1.py).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/confirmacion_urgente.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:shared_preferences/shared_preferences.dart';

final base = DateTime.parse('2026-10-17T00:00:00-03:00');
const estacion = 'CARU – estación automática Paysandú';

DateTime min(int m) => base.add(Duration(minutes: m));

/// Una publicación vista por el teléfono: minuto de `generado`, nivel, altura y
/// minuto de la lectura (por defecto, 5 min antes de `generado`).
class Pub {
  final int minuto;
  final Nivel nivel;
  final double valor;
  final int lectura;
  final String fuente;
  final Nivel? retenido;

  Pub(this.minuto, this.nivel, this.valor, {int? lectura, this.fuente = estacion, this.retenido})
      : lectura = lectura ?? minuto - 5;

  LecturaM1 get lecturaM1 => LecturaM1(generado: min(minuto), fecha: min(lectura), valorM: valor, fuente: fuente);
}

/// Lo que el teléfono recuerda entre revisiones, como en _decidir de avisos.dart.
class Telefono {
  EstadoM1 estado;
  String ultimoComo = '';

  /// [anterior]: como si viniera de la versión anterior con `ultimo_nivel` guardado.
  Telefono([Nivel? anterior]) : estado = EstadoM1(nivel: anterior);

  Nivel? ve(Pub p, {Nivel? push, DateTime? enviado}) {
    final paso = pasoM1(estado,
        anterior: estado.nivel,
        nivel: p.nivel,
        lectura: p.lecturaM1,
        retenidoAhora: p.retenido,
        push: push,
        enviado: enviado,
        ahora: min(p.minuto));
    estado = EstadoM1.desdeJson(jsonDecode(jsonEncode(paso.estado.aJson()))); // ida y vuelta por SharedPreferences
    ultimoComo = paso.como;
    return paso.sale;
  }

  List<Nivel?> secuencia(List<Pub> pubs) => [for (final p in pubs) ve(p)];
}

const at = Nivel.atencion, al = Nivel.alerta, ev = Nivel.evacuacion, no = Nivel.normal;

/// Casos del servidor en los que la app decide distinto a propósito: avisos.py no
/// avisa nunca aunque el río siga en alerta (contra su propio "nunca callar") y el
/// teléfono sí. Caso → {posición: lo que avisa la app}. Si se corrige avisos.py,
/// esta prueba falla y hay que sacarlos de acá. Detalle en docs/respaldo-m1.md.
const diferenciasConocidas = <String, Map<int, String>>{
  // La retención era de alerta pero se soltó en evacuación: el servidor da la alerta
  // por "ya avisada" en esa publicación (sin avisar). La app espera su confirmación.
  'borde servidor: retencion soltada en evacuacion y despues alerta': {3: 'alerta'},
  // Una sola publicación de evacuación tras un hueco de más de 2 h: el servidor corta
  // la historia (_racha_vencida) suponiendo que esa evacuación ya avisó.
  'borde servidor: evacuacion de una lectura tras un hueco y alerta sostenida': {4: 'alerta'},
  'con huecos #52': {6: 'alerta'}, // el mismo corte de _racha_vencida
};

void main() {
  group('regla M-1 (pasoM1)', () {
    test('la candidata no avisa; la segunda lectura la confirma', () {
      final t = Telefono();
      expect(t.secuencia([Pub(0, at, 5.5), Pub(30, al, 5.9)]), [null, null]);
      expect(t.ultimoComo, 'espera');
      expect(t.ve(Pub(60, al, 5.95)), al);
      expect(t.ultimoComo, 'confirmada');
      expect(t.ve(Pub(90, al, 6.0)), isNull); // una vez por subida
    });

    test('salto de más de 1 m no confirma; uno de hasta 1 m sí', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(30, ev, 7.5), Pub(60, ev, 9.0), Pub(80, ev, 7.6)]), [null, null, ev]);
      // Justo 1 m confirma.
      expect(Telefono(at).secuencia([Pub(0, al, 5.5), Pub(30, al, 6.5)]), [null, al]);
    });

    test('otra fuente o una lectura anterior no confirman', () {
      expect(Telefono(at).secuencia([Pub(0, al, 5.9), Pub(30, al, 5.95, fuente: 'Prefectura')]), [null, null]);
      expect(Telefono(at).secuencia([Pub(30, al, 5.9), Pub(50, al, 5.9, lectura: 0)]), [null, null]);
    });

    test('la misma lectura repetida no confirma: sale por tope a los 60 min de la candidata', () {
      final t = Telefono(at);
      final pubs = [for (final m in [30, 60, 89, 90, 120]) Pub(m, al, 5.9, lectura: 25)];
      expect(t.secuencia(pubs), [null, null, null, al, null]);
    });

    test('el tope sale aunque la lectura no confirme (salto sostenido), como el servidor', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(30, al, 6.0), Pub(60, al, 8.0), Pub(90, al, 10.0), Pub(120, al, 12.0)]),
          [null, null, al, null]);
      expect(t.ultimoComo, '');
    });

    test('dato_a_verificar solo no frena: la regla mira la altura, no la marca', () {
      // La marca no entra en LecturaM1: con alturas comparables decide el salto.
      expect(Telefono(at).secuencia([Pub(30, al, 6.1), Pub(60, al, 6.2)]), [null, al]);
    });

    test('la retención soltada al mismo nivel ya viene confirmada; a otro nivel no', () {
      expect(Telefono(at).secuencia([Pub(50, at, 5.6, retenido: al), Pub(60, al, 5.9), Pub(90, al, 5.95)]),
          [null, al, null]);
      expect(Telefono(at).secuencia([Pub(50, at, 5.6, retenido: al), Pub(60, ev, 6.7), Pub(90, ev, 6.75)]),
          [null, null, ev]);
    });

    test('una retención vista hace rato (no la publicación anterior) no confirma', () {
      // El servidor mira solo la publicación anterior (pub_antes): acá, hasta 40 min antes.
      expect(Telefono(at).secuencia([Pub(30, at, 5.6, retenido: al), Pub(200, al, 5.9), Pub(230, al, 5.95)]),
          [null, null, al]);
      expect(Telefono(at).secuencia([Pub(30, at, 5.6, retenido: al), Pub(71, al, 5.9)]), [null, null]);
      expect(Telefono(at).secuencia([Pub(30, at, 5.6, retenido: al), Pub(70, al, 5.9)]), [null, al]);
    });

    test('bajar reinicia la espera y una nueva subida vuelve a avisar', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(0, al, 5.9), Pub(30, at, 5.6), Pub(60, al, 5.9), Pub(90, al, 5.95)]),
          [null, null, null, al]);
      expect(t.secuencia([Pub(120, no, 4.0), Pub(150, al, 5.9), Pub(180, al, 5.95)]), [null, null, al]);
    });

    test('alerta → evacuación → alerta sin confirmar: sale una sola alerta', () {
      expect(
          Telefono(at).secuencia([Pub(30, al, 6.0), Pub(60, ev, 7.0), Pub(90, al, 6.1), Pub(120, al, 6.2)]),
          [null, null, al, null]);
    });

    test('evacuación confirmada: no sale una alerta redundante después', () {
      expect(
          Telefono(at).secuencia(
              [Pub(30, al, 6.0), Pub(60, ev, 7.0), Pub(90, ev, 7.1), Pub(120, al, 6.1), Pub(150, al, 6.2)]),
          [null, null, ev, null, null]);
    });

    test('sin nivel anterior conocido no avisa (como el servidor)', () {
      expect(Telefono().secuencia([Pub(0, al, 5.9), Pub(30, al, 5.95), Pub(120, al, 6.0)]), [null, null, null]);
    });

    test('sin "generado" no se puede medir el tope: se prefiere avisar', () {
      final t = Telefono(at);
      t.ve(Pub(30, al, 5.9, lectura: 25));
      final paso = pasoM1(t.estado,
          anterior: al,
          nivel: al,
          lectura: LecturaM1(generado: null, fecha: min(25), valorM: 5.9, fuente: estacion),
          retenidoAhora: null,
          ahora: min(40));
      expect(paso.sale, al);
    });

    test('la versión anterior de la app ya avisó con la primera lectura: no se repite', () {
      // Hay "ultimo_nivel" en alerta y nada guardado de M-1.
      expect(Telefono(al).secuencia([Pub(30, al, 5.9), Pub(60, al, 5.95), Pub(200, al, 6.0)]), [null, null, null]);
      // La evacuación sí es una subida nueva.
      expect(Telefono(al).secuencia([Pub(30, ev, 6.7), Pub(60, ev, 6.75)]), [null, ev]);
    });

    test('lo guardado roto o raro se lee vacío, sin romper', () {
      for (final raro in [null, 5, 'x', [], {'alerta': 'x'}, {'alerta': {'inicio': {'fecha': 'no'}}}, {'push': 1}]) {
        final e = EstadoM1.desdeJson(raro);
        expect(e.push, isNull);
        expect(e.rachas.values.every((r) => r.avisado), isTrue, reason: '$raro');
      }
    });
  });

  group('revisiones espaciadas (workmanager puede no correr)', () {
    test('más de 60 min sin revisar y el río sigue en el nivel: avisa con la lectura de ahora', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(30, al, 5.9), Pub(200, al, 5.95)]), [null, al]);
      expect(t.ultimoComo, 'confirmada');
      // Con la misma lectura (la estación no informó) sale por tope, como el servidor.
      expect(Telefono(at).secuencia([Pub(30, al, 5.9, lectura: 25), Pub(200, al, 5.9, lectura: 25)]), [null, al]);
    });

    test('más de 60 min sin revisar y la lectura no confirma (salto u otra fuente): sale por tope, como el servidor', () {
      expect(Telefono(at).secuencia([Pub(30, al, 5.9), Pub(200, al, 7.2)]), [null, al]); // salto de 1,3 m
      expect(Telefono(at).secuencia([Pub(30, al, 5.9), Pub(200, al, 5.95, fuente: 'Prefectura')]), [null, al]);
    });

    test('fuentes alternadas o salto sostenido con revisiones espaciadas no callan el urgente', () {
      final fuentes = [estacion, 'Prefectura'];
      final alternadas = [for (var i = 0; i < 6; i++) Pub(30 + 90 * i, al, 5.9, fuente: fuentes[i % 2])];
      expect(Telefono(at).secuencia(alternadas).whereType<Nivel>(), [al]);
      final saltos = [for (var i = 0; i < 6; i++) Pub(30 + 90 * i, al, 5.9 + 1.5 * (i % 2))];
      expect(Telefono(at).secuencia(saltos).whereType<Nivel>(), [al]);
      // El lector publicando cada 70 min: sale a la segunda.
      expect(Telefono(at).secuencia([Pub(0, al, 5.9), Pub(70, al, 7.5, fuente: 'Prefectura')]), [null, al]);
    });

    test('con revisiones seguidas el salto sostenido sale a los 60 min (no se vio un hueco)', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(30, al, 5.9), Pub(60, al, 7.2), Pub(95, al, 7.3)]), [null, null, al]);
    });

    test('si al volver a revisar el río ya bajó, no sale un urgente viejo', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(30, al, 5.9), Pub(300, at, 5.5), Pub(330, at, 5.5)]), [null, null, null]);
    });
  });

  group('push (el servidor ya confirmó)', () {
    test('avisa de una aunque el teléfono no haya visto la candidata', () {
      final t = Telefono(at);
      expect(t.ve(Pub(30, al, 5.9), push: al, enviado: min(32)), al);
      expect(t.ultimoComo, 'push');
      expect(t.ve(Pub(60, al, 5.95)), isNull); // el respaldo no repite
      expect(t.ve(Pub(60, al, 5.95), push: al, enviado: min(62)), isNull); // ni un segundo push
    });

    test('si el respaldo ya avisó, el push no repite', () {
      final t = Telefono(at);
      expect(t.secuencia([Pub(0, al, 5.9), Pub(30, al, 5.95)]), [null, al]);
      expect(t.ve(Pub(30, al, 5.95), push: al, enviado: min(32)), isNull);
    });

    test('push antes que el dato: queda anotado y lo usa la próxima revisión', () {
      final t = Telefono(at);
      expect(t.ve(Pub(20, at, 5.6), push: al, enviado: min(32)), isNull); // el dato todavía no muestra la subida
      expect(t.estado.push?.nivel, al);
      expect(t.ve(Pub(30, al, 5.9)), al); // la publicación de la subida, sin esperar otra lectura
      expect(t.estado.push, isNull);
    });

    test('un push anotado se descarta si un dato posterior al envío ya no muestra la subida', () {
      final t = Telefono(at);
      t.ve(Pub(20, at, 5.6), push: al, enviado: min(32));
      expect(t.ve(Pub(60, at, 5.6)), isNull);
      expect(t.estado.push, isNull);
      expect(t.secuencia([Pub(90, al, 5.9), Pub(120, al, 5.95)]), [null, al]); // una subida nueva espera su lectura
    });

    test('push de alerta con el dato ya en evacuación: avisa la alerta y la evacuación espera su lectura', () {
      final t = Telefono(at);
      expect(t.ve(Pub(30, ev, 6.7), push: al, enviado: min(32)), al);
      expect(t.ve(Pub(60, ev, 6.75)), ev);
    });
  });

  group('por decidirAvisos (preferencias y marcas)', () {
    Actual pub(String h, String nivel, double valor, {String? medido, List<String> avisos = const [], Map? retenido}) =>
        Actual.desdeJson({
          'generado': '2026-10-17T$h:00-03:00',
          'nivel': nivel,
          'avisos': avisos,
          'altura_actual': {'valor_m': valor, 'fecha': '2026-10-17T${medido ?? h}:00-03:00', 'fuente': estacion},
          'nivel_retenido': ?retenido,
        })!;
    final ahora = DateTime.parse('2026-10-17T09:59:00-03:00'); // antes de las 10: sin resumen

    Future<SharedPreferences> prefs(Map<String, Object> v) async {
      SharedPreferences.setMockInitialValues({claveVersionAvisos: 1, claveUrl: 'https://ejemplo.test/data/', ...v});
      return SharedPreferences.getInstance();
    }

    Future<List<String>> titulos(Actual a, SharedPreferences p) async =>
        [for (final x in await decidirAvisos(a, p, ahora)) x.titulo];

    test('candidata, confirmación con dato_a_verificar, y una sola vez', () async {
      final p = await prefs({claveUrgente: true, claveResumen: true, claveUltimoNivel: 'atencion'});
      expect(await titulos(pub('08:30', 'alerta', 5.9, avisos: ['dato_a_verificar']), p), isEmpty);
      final avisos = await decidirAvisos(pub('09:00', 'alerta', 5.95, avisos: ['dato_a_verificar']), p, ahora);
      expect(avisos.single.titulo, 'Río Uruguay: subió a ALERTA');
      expect(avisos.single.texto, contains('Dato a verificar por CARU.'));
      expect(await titulos(pub('09:30', 'alerta', 6.0), p), isEmpty);
    });

    test('nivel_retenido del lector llega al teléfono', () async {
      final p = await prefs({claveUrgente: true, claveUltimoNivel: 'atencion'});
      expect(await titulos(pub('08:50', 'atencion', 5.6, retenido: {'nivel': 'alerta'}), p), isEmpty);
      expect(await titulos(pub('09:00', 'alerta', 5.9), p), ['Río Uruguay: subió a ALERTA']);
    });

    test('urgente apagado: no avisa, pero la subida avanza (no sale tarde al prenderlo)', () async {
      final p = await prefs({claveUrgente: false, claveUltimoNivel: 'atencion'});
      expect(await titulos(pub('08:30', 'alerta', 5.9), p), isEmpty);
      expect(await titulos(pub('09:00', 'alerta', 5.95), p), isEmpty);
      await p.setBool(claveUrgente, true);
      expect(await titulos(pub('09:30', 'alerta', 6.0), p), isEmpty);
    });

    test('"Solo evacuación": la alerta confirmada no avisa; la evacuación sí', () async {
      final p = await prefs({claveUrgente: true, claveUrgenteDesde: 'evacuacion', claveUltimoNivel: 'atencion'});
      expect(await titulos(pub('08:00', 'alerta', 5.9), p), isEmpty);
      expect(await titulos(pub('08:30', 'alerta', 5.95), p), isEmpty);
      expect(await titulos(pub('09:00', 'evacuacion', 6.7), p), isEmpty);
      expect(await titulos(pub('09:30', 'evacuacion', 6.75), p), ['Río Uruguay: subió a EVACUACIÓN']);
    });

    test('instalación nueva (P-04): todo apagado hasta elegir, nada sale', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      await prepararPrimerArranque(p);
      await p.setString(claveUltimoNivel, 'atencion');
      expect(await titulos(pub('08:30', 'alerta', 5.9), p), isEmpty);
      expect(await titulos(pub('09:00', 'alerta', 5.95), p), isEmpty);
    });

    test('push que llegó antes que el dato: el respaldo avisa con la publicación de la subida', () async {
      final p = await prefs({claveUrgente: true, claveUltimoNivel: 'atencion'});
      final viejo = pub('08:20', 'atencion', 5.6);
      final avisos = <Aviso>[];
      await atenderMensajePush({'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'paysandu'}, p,
          (_) async => Datos(actual: viejo), (a) async => avisos.add(a),
          enviado: DateTime.parse('2026-10-17T08:32:00-03:00'), reloj: () => ahora, espera: Duration.zero);
      expect(avisos, [avisoUrgenteSinDato]);
      expect(await titulos(pub('08:30', 'alerta', 5.9), p), ['Río Uruguay: subió a ALERTA']);
      expect(await titulos(pub('09:00', 'alerta', 5.95), p), isEmpty);
    });

    test('push que no pudo bajar el dato: también queda anotado', () async {
      final p = await prefs({claveUrgente: true, claveUltimoNivel: 'atencion'});
      final avisos = <Aviso>[];
      await atenderMensajePush({'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'paysandu'}, p,
          (_) => Future.error(Exception('sin red')), (a) async => avisos.add(a),
          enviado: DateTime.parse('2026-10-17T08:32:00-03:00'), reloj: () => ahora, espera: Duration.zero);
      expect(avisos, [avisoUrgenteSinDato]);
      expect(leerEstadoM1(p).push?.nivel, Nivel.alerta);
      expect(await titulos(pub('08:30', 'alerta', 5.9), p), ['Río Uruguay: subió a ALERTA']);
    });

    test('el teléfono avisó antes que el servidor: el push de la misma subida no se repite', () async {
      // Lo último que vio es de más de 20 min antes del envío, pero él mismo avisó esa subida hace poco.
      final p = await prefs({claveUrgente: true, claveUltimoNivel: 'atencion'});
      expect(await titulos(pub('08:00', 'alerta', 5.9), p), isEmpty);
      expect(await titulos(pub('08:30', 'alerta', 5.95), p), ['Río Uruguay: subió a ALERTA']);
      final avisos = <Aviso>[];
      await atenderMensajePush({'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'paysandu'}, p,
          (_) async => Datos(actual: pub('09:00', 'alerta', 6.0)), (a) async => avisos.add(a),
          enviado: DateTime.parse('2026-10-17T09:15:00-03:00'), reloj: () => ahora, espera: Duration.zero);
      expect(avisos, isEmpty);
    });

    test('una bajada no vista: el push de horas después sí avisa', () async {
      final p = await prefs({claveUrgente: true, claveUltimoNivel: 'atencion'});
      await titulos(pub('03:00', 'alerta', 5.9), p);
      expect(await titulos(pub('03:30', 'alerta', 5.95), p), ['Río Uruguay: subió a ALERTA']);
      final avisos = <Aviso>[];
      await atenderMensajePush({'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'paysandu'}, p,
          (_) async => Datos(actual: pub('09:00', 'alerta', 6.0)), (a) async => avisos.add(a),
          enviado: DateTime.parse('2026-10-17T09:05:00-03:00'), reloj: () => ahora, espera: Duration.zero);
      expect(avisos.single.titulo, 'Río Uruguay: subió a ALERTA');
    });

    test('caché vieja: una publicación anterior a la última vista no toca nada', () async {
      final p = await prefs({claveUrgente: true, claveUltimoNivel: 'atencion'});
      expect(await titulos(pub('08:30', 'alerta', 5.9), p), isEmpty);
      expect(await titulos(pub('09:00', 'alerta', 5.95), p), ['Río Uruguay: subió a ALERTA']);
      final guardado = p.getString(claveConfirmacionUrgente);
      expect(await titulos(pub('08:00', 'atencion', 5.6), p), isEmpty); // copia vieja
      expect(p.getString(claveConfirmacionUrgente), guardado);
      expect(await titulos(pub('09:30', 'alerta', 6.0), p), isEmpty); // no se repite
    });

    test('todo en una sola clave: migra ultimo_nivel y ultimo_nivel_generado y los borra', () async {
      final p = await prefs({
        claveUrgente: true,
        claveUltimoNivel: 'atencion',
        claveUltimoGenerado: '2026-10-17T11:00:00.000Z', // 08:00 en Uruguay
      });
      expect(nivelVisto(p), Nivel.atencion);
      expect(await titulos(pub('08:30', 'alerta', 5.9), p), isEmpty);
      expect(p.containsKey(claveUltimoNivel), isFalse);
      expect(p.containsKey(claveUltimoGenerado), isFalse);
      final e = leerEstadoM1(p);
      expect(e.nivel, Nivel.alerta);
      expect(e.visto, DateTime.parse('2026-10-17T08:30:00-03:00'));
      expect(e.rachas[Nivel.alerta]?.avisado, isFalse);
      // Una copia de las claves viejas que quedara no pisa lo nuevo.
      await p.setString(claveUltimoNivel, 'normal');
      expect(nivelVisto(p), Nivel.alerta);
    });
  });

  group('los mismos casos que decidió el servidor (avisos.py)', () {
    final datos = jsonDecode(File('test/fixtures/casos_m1_servidor.json').readAsStringSync()) as Map<String, dynamic>;
    final fuentes = (datos['fuentes'] as List).cast<String>();
    final casos = (datos['casos'] as List).cast<Map<String, dynamic>>();

    test('hay casos de las dos generaciones y urgentes de los dos niveles', () {
      expect(DateTime.parse(datos['base'] as String), base);
      expect(casos.length, greaterThan(200));
      final todos = casos.expand((c) => c['urgentes'] as List).toSet();
      expect(todos, containsAll(['alerta', 'evacuacion', null]));
    });

    test('viendo solo algunas publicaciones (revisiones salteadas): nunca con la primera, nunca dos veces, '
        'y avisa si el servidor avisó y vio dos lecturas del nivel a 60 min o más', () {
      final azar = Random(20261104);
      var vivacidadComprobada = 0;
      for (final caso in casos) {
        final filas = (caso['pubs'] as List).cast<List>();
        final servidor = (caso['urgentes'] as List).cast<String?>();
        final niveles = [for (final f in filas) nivelDesdeTexto(f[1] as String)];
        for (var vuelta = 0; vuelta < 5; vuelta++) {
          final t = Telefono();
          Nivel? antes;
          final avisadoEnLaSubida = <Nivel, bool>{};
          final vistas = <int>[];
          final salidas = <int, Nivel>{};
          for (var i = 0; i < filas.length; i++) {
            if (azar.nextDouble() < 0.5) continue; // esta revisión no corrió
            final f = filas[i];
            final nivel = niveles[i];
            vistas.add(i);
            final sale = t.ve(Pub(f[0] as int, nivel, (f[2] as num).toDouble(),
                lectura: f[3] as int, fuente: fuentes[f[4] as int]));
            for (final x in nivelesUrgentes) {
              if (ordenDeNivel(nivel) < ordenDeNivel(x)) avisadoEnLaSubida.remove(x);
            }
            if (sale != null) {
              salidas[i] = sale;
              expect(sale, nivel, reason: 'solo avisa el nivel que muestra el dato');
              expect(antes != null && ordenDeNivel(antes) >= ordenDeNivel(sale), isTrue,
                  reason: 'nunca con la primera lectura vista de la subida: ${caso['nombre']}');
              expect(avisadoEnLaSubida[sale], isNull, reason: 'dos veces en la misma subida: ${caso['nombre']}');
              avisadoEnLaSubida[sale] = true;
            }
            antes = nivel;
          }
          // Vivacidad: por cada subida (racha continua con x o más) en la que el servidor
          // avisó x, si el teléfono vio antes una publicación más baja y vio 2 o más
          // lecturas de x con 60 min o más entre ellas, tiene que haber avisado x (o más).
          for (final x in nivelesUrgentes) {
            var i = 0;
            while (i < filas.length) {
              if (ordenDeNivel(niveles[i]) < ordenDeNivel(x)) {
                i++;
                continue;
              }
              var j = i;
              while (j + 1 < filas.length && ordenDeNivel(niveles[j + 1]) >= ordenDeNivel(x)) {
                j++;
              }
              final servidorAviso = [for (var k = i; k <= j; k++) servidor[k]].contains(nivelATexto(x));
              final antesVista = vistas.where((k) => k < i);
              final base = antesVista.isNotEmpty && ordenDeNivel(niveles[antesVista.last]) < ordenDeNivel(x);
              final deX = [for (final k in vistas) if (k >= i && k <= j && niveles[k] == x) filas[k][0] as int];
              if (servidorAviso && base && deX.length >= 2 && deX.last - deX.first >= 60) {
                vivacidadComprobada++;
                final avisoTelefono = salidas.entries
                    .any((e) => e.key >= i && e.key <= j && ordenDeNivel(e.value) >= ordenDeNivel(x));
                expect(avisoTelefono, isTrue, reason: 'calló ${nivelATexto(x)}: ${caso['nombre']} vistas=$vistas');
              }
              i = j + 1;
            }
          }
        }
      }
      expect(vivacidadComprobada, greaterThan(100)); // que la propiedad se haya comprobado de verdad
    });

    for (final caso in casos) {
      test(caso['nombre'], () {
        final t = Telefono();
        final salidas = <String?>[];
        for (final f in (caso['pubs'] as List).cast<List>()) {
          final pub = Pub(f[0] as int, nivelDesdeTexto(f[1] as String), (f[2] as num).toDouble(),
              lectura: f[3] as int, fuente: fuentes[f[4] as int], retenido: f[5] == null ? null : nivelDesdeTexto(f[5] as String));
          final sale = t.ve(pub);
          salidas.add(sale == null ? null : nivelATexto(sale));
        }
        final esperado = [...(caso['urgentes'] as List).cast<String?>()];
        final distinto = diferenciasConocidas[caso['nombre']] ?? const {};
        for (final e in distinto.entries) {
          expect(esperado[e.key], isNull, reason: 'el servidor ya avisa acá: sacar de diferenciasConocidas');
          esperado[e.key] = e.value;
        }
        expect(salidas, esperado, reason: '${caso['pubs']}');
      });
    }
  });
}

/// Reglas de los avisos de la Fase 4 (las mismas de lector/avisos.py), marcas
/// compartidas entre el push y la revisión de respaldo, validación de los
/// mensajes push, textos, migración de preferencias y temas. Sin internet.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/push.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un actual.json armado a mano. Las horas van en hora de Uruguay ("2026-10-09T08:30").
Actual actualEn(
  String generado, {
  String nivel = 'alerta',
  double valor = 5.95,
  String? medido,
  String? prefectura = '2026-10-09T06:00',
  double prefecturaM = 5.85,
  double? variacion = -0.13,
  String? estado = 'baja',
  String periodo = '24 hs',
  List<String> avisos = const [],
}) =>
    Actual.desdeJson({
      'generado': '$generado:00-03:00',
      'nivel': nivel,
      'avisos': avisos,
      'altura_actual': {'valor_m': valor, 'fecha': '${medido ?? generado}:00-03:00', 'periodo': '30 min'},
      'lectura_prefectura': prefectura == null
          ? null
          : {
              'valor_m': prefecturaM,
              'fecha': '$prefectura:00-03:00',
              'variacion_m': variacion,
              'periodo': periodo,
              'estado': estado,
            },
    })!;

DateTime hora(String h) => DateTime.parse('$h:00-03:00');

Future<SharedPreferences> prefsCon(Map<String, Object> valores) async {
  SharedPreferences.setMockInitialValues(valores);
  return SharedPreferences.getInstance();
}

/// Preferencias ya migradas: urgente desde alerta y resumen prendidos.
const todoPrendido = <String, Object>{
  claveVersionAvisos: 1,
  claveUrgente: true,
  claveUrgenteDesde: 'alerta',
  claveResumen: true,
  claveUrl: 'https://ejemplo.test/data/',
};

List<TipoAviso> tipos(List<Aviso> avisos) => [for (final a in avisos) a.tipo];

void main() {
  group('aviso urgente', () {
    // A las 08:00 todavía no hay resumen (antes de las 10, sin Prefectura del día).
    Actual a(String nivel) => actualEn('2026-10-09T08:00', nivel: nivel, prefectura: '2026-10-08T06:00');
    final ahora = hora('2026-10-09T08:05');

    test('avisa al subir a alerta y a evacuación, una sola vez cada subida', () async {
      final prefs = await prefsCon(todoPrendido);
      expect(await decidirAvisos(a('normal'), prefs, ahora), isEmpty); // primera vez: solo se recuerda
      expect(await decidirAvisos(a('atencion'), prefs, ahora), isEmpty); // normal → atención no avisa
      expect(tipos(await decidirAvisos(a('alerta'), prefs, ahora)), [TipoAviso.urgente]);
      expect(await decidirAvisos(a('alerta'), prefs, ahora), isEmpty); // la misma subida no se repite
      final evacuacion = await decidirAvisos(a('evacuacion'), prefs, ahora);
      expect(evacuacion.single.titulo, 'Río Uruguay: subió a EVACUACIÓN');
    });

    test('no avisa por bajadas, y avisa de nuevo si vuelve a subir', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'evacuacion'});
      expect(await decidirAvisos(a('alerta'), prefs, ahora), isEmpty);
      expect(await decidirAvisos(a('normal'), prefs, ahora), isEmpty);
      expect(tipos(await decidirAvisos(a('alerta'), prefs, ahora)), [TipoAviso.urgente]);
    });

    test('"sin dato" en el medio se saltea: se compara con el último nivel con dato', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      // Altura de hace 3 días: el nivel vigente es "sin dato" y no se recuerda.
      final viejo = actualEn('2026-10-09T08:00', medido: '2026-10-06T08:00', prefectura: null);
      expect(await decidirAvisos(viejo, prefs, ahora), isEmpty);
      expect(prefs.getString(claveUltimoNivel), 'atencion');
      final sinNivel = actualEn('2026-10-09T08:00', nivel: 'sin_dato', prefectura: null);
      expect(await decidirAvisos(sinNivel, prefs, ahora), isEmpty);
      expect(prefs.getString(claveUltimoNivel), 'atencion');
      expect(tipos(await decidirAvisos(a('alerta'), prefs, ahora)), [TipoAviso.urgente]);

      // alerta → sin dato → alerta no es una subida.
      expect(await decidirAvisos(sinNivel, prefs, ahora), isEmpty);
      expect(await decidirAvisos(a('alerta'), prefs, ahora), isEmpty);
    });

    test('"Solo evacuación" no avisa al subir a alerta', () async {
      final prefs = await prefsCon({...todoPrendido, claveUrgenteDesde: 'evacuacion', claveUltimoNivel: 'normal'});
      expect(await decidirAvisos(a('alerta'), prefs, ahora), isEmpty);
      expect(tipos(await decidirAvisos(a('evacuacion'), prefs, ahora)), [TipoAviso.urgente]);
    });

    test('apagado no avisa, pero igual recuerda el nivel', () async {
      final prefs = await prefsCon({...todoPrendido, claveUrgente: false, claveUltimoNivel: 'normal'});
      expect(await decidirAvisos(a('alerta'), prefs, ahora), isEmpty);
      expect(prefs.getString(claveUltimoNivel), 'alerta');
    });
  });

  group('resumen del día', () {
    test('sale con la lectura de Prefectura del día, uno solo por día', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'alerta'});
      final temprano = actualEn('2026-10-09T05:30', prefectura: '2026-10-08T06:00');
      expect(await decidirAvisos(temprano, prefs, hora('2026-10-09T05:35')), isEmpty);
      final conPrefectura = actualEn('2026-10-09T08:30');
      final avisos = await decidirAvisos(conPrefectura, prefs, hora('2026-10-09T08:35'));
      expect(avisos.single.titulo, 'Río hoy: 5,85 m · Alerta');
      expect(avisos.single.texto, 'Bajó 13 cm en 24 h. Abrí la app para ver el dato en tiempo real.');
      expect(prefs.getString(claveUltimoResumen), '2026-10-09');
      // Más tarde el mismo día: nada.
      expect(await decidirAvisos(actualEn('2026-10-09T15:00'), prefs, hora('2026-10-09T15:05')), isEmpty);
    });

    test('sin Prefectura sale a las 10 con la estación, no antes', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'alerta'});
      final antes = actualEn('2026-10-09T09:59', prefectura: '2026-10-08T06:00');
      expect(await decidirAvisos(antes, prefs, hora('2026-10-09T09:59')), isEmpty);
      final alas10 = actualEn('2026-10-09T10:00', medido: '2026-10-09T09:30', prefectura: '2026-10-08T06:00');
      final avisos = await decidirAvisos(alas10, prefs, hora('2026-10-09T10:01'));
      expect(avisos.single.titulo, 'Río hoy: 5,95 m · Alerta');
      expect(avisos.single.texto, contains('estación automática de CARU de las 09:30'));
      expect(avisos.single.texto, isNot(contains('24 h'))); // no se inventa la variación de 24 h
    });

    test('el día es el de Uruguay (UTC-3), no el UTC', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'alerta'});
      // 23:30 del 9 en Uruguay es el 10 en UTC: sigue siendo el día 9.
      final noche = actualEn('2026-10-09T23:30');
      expect(tipos(await decidirAvisos(noche, prefs, hora('2026-10-09T23:31'))), [TipoAviso.resumen]);
      expect(prefs.getString(claveUltimoResumen), '2026-10-09');
      // A las 00:30 del 10, antes de las 10 y con la Prefectura del 9: todavía no.
      final madrugada = actualEn('2026-10-10T00:30');
      expect(await decidirAvisos(madrugada, prefs, hora('2026-10-10T00:31')), isEmpty);
      // Llega la Prefectura del 10: nuevo día, nuevo resumen.
      final otroDia = actualEn('2026-10-10T08:00', prefectura: '2026-10-10T06:00');
      expect(tipos(await decidirAvisos(otroDia, prefs, hora('2026-10-10T08:01'))), [TipoAviso.resumen]);
    });

    test('con el río normal o sin dato no llega nada', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'normal'});
      expect(await decidirAvisos(actualEn('2026-10-09T11:00', nivel: 'normal'), prefs, hora('2026-10-09T11:01')),
          isEmpty);
      final viejo = actualEn('2026-10-09T11:00', medido: '2026-10-06T11:00');
      expect(await decidirAvisos(viejo, prefs, hora('2026-10-09T11:01')), isEmpty);
      expect(prefs.getString(claveUltimoResumen), isNull);
    });

    test('en atención también sale', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final avisos = await decidirAvisos(actualEn('2026-10-09T08:30', nivel: 'atencion'), prefs, hora('2026-10-09T08:31'));
      expect(avisos.single.titulo, 'Río hoy: 5,85 m · Atención');
    });

    test('un dato de ayer no sale como "Río hoy"', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'alerta'});
      final ayer = actualEn('2026-10-09T23:00');
      expect(await decidirAvisos(ayer, prefs, hora('2026-10-10T00:30')), isEmpty);
    });

    test('apagado no sale ni se marca', () async {
      final prefs = await prefsCon({...todoPrendido, claveResumen: false, claveUltimoNivel: 'alerta'});
      expect(await decidirAvisos(actualEn('2026-10-09T08:30'), prefs, hora('2026-10-09T08:31')), isEmpty);
      expect(prefs.getString(claveUltimoResumen), isNull);
    });

    test('con la app a la vista se marca el día sin notificar', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'alerta'});
      expect(await decidirAvisos(actualEn('2026-10-09T08:30'), prefs, hora('2026-10-09T08:31'), origen: Origen.app),
          isEmpty);
      expect(prefs.getString(claveUltimoResumen), '2026-10-09');
      expect(await decidirAvisos(actualEn('2026-10-09T09:00'), prefs, hora('2026-10-09T09:01')), isEmpty);
    });

    test('si en la misma pasada sube a alerta, queda solo el urgente', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final avisos = await decidirAvisos(actualEn('2026-10-09T08:30'), prefs, hora('2026-10-09T08:31'));
      expect(tipos(avisos), [TipoAviso.urgente]);
      expect(prefs.getString(claveUltimoResumen), '2026-10-09');
    });

    test('resumenListo replica a resumen_listo de avisos.py', () {
      expect(resumenListo(actualEn('2026-10-09T07:00'), Nivel.alerta), FuenteResumen.prefectura);
      expect(resumenListo(actualEn('2026-10-09T09:59', prefectura: null), Nivel.alerta), isNull);
      expect(resumenListo(actualEn('2026-10-09T10:00', prefectura: null), Nivel.alerta), FuenteResumen.estacion);
      expect(resumenListo(actualEn('2026-10-09T12:00'), Nivel.normal), isNull);
      expect(resumenListo(actualEn('2026-10-09T12:00'), Nivel.sinDato), isNull);
      expect(resumenListo(const Actual(nivel: Nivel.alerta), Nivel.alerta), isNull); // sin "generado"
    });
  });

  group('marcas compartidas entre el push y el respaldo', () {
    Datos datos(Actual a) => Datos(actual: a);

    test('el urgente que mostró el respaldo no se repite con el push, ni al revés', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final alerta = actualEn('2026-10-09T08:00', prefectura: '2026-10-08T06:00');
      final ahora = hora('2026-10-09T08:01');
      expect(tipos(await decidirAvisos(alerta, prefs, ahora)), [TipoAviso.urgente]);
      final push = await avisosDePush({'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'paysandu'}, prefs,
          (_) async => datos(alerta),
          reloj: () => ahora, esperas: const []);
      expect(push, isEmpty);

      final evacuacion = actualEn('2026-10-09T09:00', nivel: 'evacuacion', valor: 7.0, prefectura: '2026-10-08T06:00');
      final porPush = await avisosDePush({'tipo': 'urgente', 'nivel': 'evacuacion', 'ciudad': 'paysandu'}, prefs,
          (_) async => datos(evacuacion),
          reloj: () => ahora, esperas: const []);
      expect(porPush.single.titulo, 'Río Uruguay: subió a EVACUACIÓN');
      expect(await decidirAvisos(evacuacion, prefs, ahora), isEmpty);
    });

    test('el resumen del día sale una sola vez entre el push y el respaldo', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'alerta'});
      final a = actualEn('2026-10-09T08:30');
      final ahora = hora('2026-10-09T08:31');
      final push = await avisosDePush({'tipo': 'resumen', 'fuente': 'prefectura', 'ciudad': 'paysandu'}, prefs,
          (_) async => datos(a),
          reloj: () => ahora, esperas: const []);
      expect(tipos(push), [TipoAviso.resumen]);
      expect(await decidirAvisos(a, prefs, ahora), isEmpty);
      final otraVez = await avisosDePush({'tipo': 'resumen', 'fuente': 'prefectura', 'ciudad': 'paysandu'}, prefs,
          (_) async => datos(a),
          reloj: () => ahora, esperas: const []);
      expect(otraVez, isEmpty);
    });

    test('dos revisiones a la vez en el mismo isolate avisan una sola vez', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final alerta = actualEn('2026-10-09T08:00', prefectura: '2026-10-08T06:00');
      final ahora = hora('2026-10-09T08:01');
      final juntas = await Future.wait([
        decidirAvisos(alerta, prefs, ahora, origen: Origen.app),
        decidirAvisos(alerta, prefs, ahora, origen: Origen.push),
      ]);
      expect(juntas.expand((a) => a).where((a) => a.tipo == TipoAviso.urgente), hasLength(1));
    });

    test('las marcas que escribe otro isolate se ven (reload)', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final alerta = actualEn('2026-10-09T08:00', prefectura: '2026-10-08T06:00');
      // Otro isolate ya avisó la subida: lo que queda guardado (no en la copia en memoria).
      SharedPreferences.setMockInitialValues({...todoPrendido, claveUltimoNivel: 'alerta'});
      expect(await decidirAvisos(alerta, prefs, hora('2026-10-09T08:01')), isEmpty);
    });
  });

  group('push', () {
    final alerta = actualEn('2026-10-09T08:00', prefectura: '2026-10-08T06:00');
    final ahora = hora('2026-10-09T08:01');
    const urgente = {'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'paysandu'};

    test('validación de los mensajes', () {
      expect(validarMensajePush(urgente)!.nivel, Nivel.alerta);
      expect(validarMensajePush({'tipo': 'urgente', 'nivel': 'evacuacion', 'ciudad': 'paysandu'})!.nivel,
          Nivel.evacuacion);
      expect(validarMensajePush({'tipo': 'resumen', 'fuente': 'estacion', 'ciudad': 'paysandu'})!.tipo,
          TipoAviso.resumen);
      for (final malo in <Map<String, Object?>>[
        {},
        {'tipo': 'urgente', 'nivel': 'atencion', 'ciudad': 'paysandu'},
        {'tipo': 'urgente', 'nivel': 'normal', 'ciudad': 'paysandu'},
        {'tipo': 'urgente', 'ciudad': 'paysandu'},
        {'tipo': 'urgente', 'nivel': 'alerta', 'ciudad': 'salto'},
        {'tipo': 'urgente', 'nivel': 'alerta'},
        {'tipo': 'resumen', 'fuente': 'otra', 'ciudad': 'paysandu'},
        {'tipo': 'resumen', 'ciudad': 'paysandu'},
        {'tipo': 'texto', 'title': 'Evacuen ya', 'ciudad': 'paysandu'},
        {'tipo': 'URGENTE', 'nivel': 'alerta', 'ciudad': 'paysandu'},
        {'tipo': 1, 'nivel': 'alerta', 'ciudad': 'paysandu'},
      ]) {
        expect(validarMensajePush(malo), isNull, reason: '$malo');
      }
    });

    test('el texto sale de actual.json, nunca del mensaje', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final avisos = await avisosDePush(
          {...urgente, 'title': 'Texto falso', 'body': 'Evacuen ya'}, prefs, (_) async => Datos(actual: alerta),
          reloj: () => ahora, esperas: const []);
      expect(avisos.single.titulo, 'Río Uruguay: subió a ALERTA');
      expect(avisos.single.texto, isNot(contains('Evacuen')));
    });

    test('un mensaje inválido o de algo que no se pidió no baja nada', () async {
      var bajadas = 0;
      Future<Datos> bajar(String _) async {
        bajadas++;
        return Datos(actual: alerta);
      }

      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      expect(await avisosDePush({'tipo': 'urgente', 'nivel': 'alerta'}, prefs, bajar, esperas: const []), isEmpty);
      await prefs.setBool(claveUrgente, false);
      expect(await avisosDePush(urgente, prefs, bajar, esperas: const []), isEmpty);
      await prefs.setBool(claveUrgente, true);
      await prefs.setString(claveUrgenteDesde, 'evacuacion');
      expect(await avisosDePush(urgente, prefs, bajar, esperas: const []), isEmpty);
      await prefs.setBool(claveResumen, false);
      expect(await avisosDePush({'tipo': 'resumen', 'fuente': 'prefectura', 'ciudad': 'paysandu'}, prefs, bajar,
              esperas: const []),
          isEmpty);
      expect(bajadas, 0);
    });

    test('sin dato bajado: el urgente avisa sin inventar nada; el resumen, nada', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      Future<Datos> sinRed(String _) async => Datos(actual: alerta, sinConexion: true); // la copia guardada no sirve
      final avisos = await avisosDePush(urgente, prefs, sinRed, reloj: () => ahora, esperas: const []);
      expect(avisos.single.titulo, 'Río Uruguay: hay novedades');
      expect(avisos.single.texto, isNot(contains(' m ')));
      expect(prefs.getString(claveUltimoNivel), 'atencion'); // no cuenta como visto
      expect(
          await avisosDePush({'tipo': 'resumen', 'fuente': 'prefectura', 'ciudad': 'paysandu'}, prefs, sinRed,
              reloj: () => ahora, esperas: const []),
          isEmpty);
      Future<Datos> falla(String _) => Future.error(Exception('sin red'));
      expect((await avisosDePush(urgente, prefs, falla, reloj: () => ahora, esperas: const [])).single,
          same(avisoUrgenteSinDato));
    });

    test('sin la dirección de los datos guardada, el urgente avisa sin dato', () async {
      final prefs = await prefsCon({...todoPrendido}..remove(claveUrl));
      expect(await avisosDePush(urgente, prefs, (_) async => Datos(actual: alerta), esperas: const []),
          [avisoUrgenteSinDato]);
    });

    test('si actual.json todavía no se publicó, se vuelve a bajar', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final viejo = actualEn('2026-10-09T07:30', nivel: 'atencion', prefectura: '2026-10-08T06:00');
      var bajadas = 0;
      final avisos = await avisosDePush(urgente, prefs, (_) async => Datos(actual: ++bajadas < 2 ? viejo : alerta),
          reloj: () => ahora, esperas: const [Duration.zero, Duration.zero]);
      expect(bajadas, 2);
      expect(avisos.single.titulo, 'Río Uruguay: subió a ALERTA');
    });

    test('si después de esperar sigue sin publicarse, avisa sin dato (y el respaldo avisa después)', () async {
      final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
      final viejo = actualEn('2026-10-09T07:30', nivel: 'atencion', prefectura: '2026-10-08T06:00');
      var bajadas = 0;
      final avisos = await avisosDePush(urgente, prefs, (_) async {
        bajadas++;
        return Datos(actual: viejo);
      }, reloj: () => ahora, esperas: const [Duration.zero, Duration.zero]);
      expect(bajadas, 3);
      expect(avisos, [avisoUrgenteSinDato]);
      expect(tipos(await decidirAvisos(alerta, prefs, ahora)), [TipoAviso.urgente]);
    });

    group('con la hora de envío de FCM', () {
      final enviado = hora('2026-10-09T08:03'); // la publicación de la subida es de las 08:00

      test('si el teléfono ya vio la publicación de la subida, el push no la repite', () async {
        final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
        expect(tipos(await decidirAvisos(alerta, prefs, ahora)), [TipoAviso.urgente]); // la vio el respaldo
        expect(
            await avisosDePush(urgente, prefs, (_) async => Datos(actual: alerta),
                enviado: enviado, reloj: () => ahora, esperas: const []),
            isEmpty);
      });

      test('una bajada que el teléfono no vio no hace perder la subida siguiente', () async {
        // Lo último que vio fue alerta a las 03:00; el río bajó y volvió a subir sin que revisara.
        final prefs = await prefsCon(
            {...todoPrendido, claveUltimoNivel: 'alerta', claveUltimoGenerado: '2026-10-09T06:00:00.000Z'});
        final avisos = await avisosDePush(urgente, prefs, (_) async => Datos(actual: alerta),
            enviado: enviado, reloj: () => ahora, esperas: const []);
        expect(avisos.single.titulo, 'Río Uruguay: subió a ALERTA');
        // Sin la hora de envío no se puede saber: no se arriesga a repetir.
        final otro = await prefsCon(
            {...todoPrendido, claveUltimoNivel: 'alerta', claveUltimoGenerado: '2026-10-09T06:00:00.000Z'});
        expect(
            await avisosDePush(urgente, otro, (_) async => Datos(actual: alerta), reloj: () => ahora, esperas: const []),
            isEmpty);
      });

      test('un push viejo (teléfono apagado) con el río ya bajo no avisa nada', () async {
        final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
        final hoy = actualEn('2026-10-16T08:00', nivel: 'normal', prefectura: '2026-10-16T06:00');
        var bajadas = 0;
        final avisos = await avisosDePush(urgente, prefs, (_) async {
          bajadas++;
          return Datos(actual: hoy);
        }, enviado: enviado, reloj: () => hora('2026-10-16T08:05'), esperas: const [Duration.zero]);
        expect(avisos, isEmpty);
        expect(bajadas, 1); // el dato es posterior al envío: no hay que esperar
      });

      test('el dato anterior al envío y más bajo se vuelve a bajar y, si sigue, avisa sin dato', () async {
        final prefs = await prefsCon({...todoPrendido, claveUltimoNivel: 'atencion'});
        final viejo = actualEn('2026-10-09T07:30', nivel: 'atencion', prefectura: '2026-10-08T06:00');
        var bajadas = 0;
        final avisos = await avisosDePush(urgente, prefs, (_) async {
          bajadas++;
          return Datos(actual: viejo);
        }, enviado: enviado, reloj: () => ahora, esperas: const [Duration.zero]);
        expect(bajadas, 2);
        expect(avisos, [avisoUrgenteSinDato]);
      });
    });

    test('un teléfono sin nivel anterior le cree al push urgente; el respaldo no', () async {
      final prefs = await prefsCon(todoPrendido);
      expect(await decidirAvisos(alerta, prefs, ahora), isEmpty);
      final otro = await prefsCon(todoPrendido);
      final avisos =
          await avisosDePush(urgente, otro, (_) async => Datos(actual: alerta), reloj: () => ahora, esperas: const []);
      expect(tipos(avisos), [TipoAviso.urgente]);
    });
  });

  group('textos', () {
    test('urgente: altura, fecha y hora completas, a verificar y la alerta oficial', () {
      final a = actualEn('2026-10-09T12:25', medido: '2026-10-09T12:00', avisos: ['dato_a_verificar']);
      final aviso = avisoUrgente(a, Nivel.alerta);
      expect(aviso.titulo, 'Río Uruguay: subió a ALERTA');
      expect(
          aviso.texto,
          'Altura en Paysandú: 5,95 m (el 9/10 a las 12:00). Dato a verificar por CARU. '
          'Fuente: CARU. La alerta oficial la dan el Sinae y el Cecoed.');
    });

    test('resumen con la variación de 24 h de Prefectura', () {
      String texto(Actual a) => avisoResumen(a, Nivel.alerta, FuenteResumen.prefectura).texto;
      expect(texto(actualEn('2026-10-09T08:30', variacion: 0.3, estado: 'crece')),
          'Subió 30 cm en 24 h. Abrí la app para ver el dato en tiempo real.');
      expect(texto(actualEn('2026-10-09T08:30', variacion: -1.19, estado: 'baja')), startsWith('Bajó 1,19 m en 24 h.'));
      expect(texto(actualEn('2026-10-09T08:30', variacion: 0, estado: 'estacionado')), startsWith('Sin cambios en 24 h.'));
      expect(texto(actualEn('2026-10-09T08:30', variacion: 0.05, estado: null)), startsWith('Subió 5 cm en 24 h.'));
      // Sin variación o con otro período no se dice nada de 24 h.
      expect(texto(actualEn('2026-10-09T08:30', variacion: null)), 'Abrí la app para ver el dato en tiempo real.');
      expect(texto(actualEn('2026-10-09T08:30', periodo: '12 hs')), 'Abrí la app para ver el dato en tiempo real.');
      expect(texto(actualEn('2026-10-09T08:30', avisos: ['dato_a_verificar'])),
          'Bajó 13 cm en 24 h. Dato a verificar por CARU. Abrí la app para ver el dato en tiempo real.');
    });

    test('resumen con la estación: dice la fuente', () {
      final aviso = avisoResumen(actualEn('2026-10-09T10:20', medido: '2026-10-09T10:00', prefectura: null),
          Nivel.evacuacion, FuenteResumen.estacion);
      expect(aviso.titulo, 'Río hoy: 5,95 m · Evacuación');
      expect(
          aviso.texto,
          'Dato de la estación automática de CARU de las 10:00 (todavía no llegó la lectura de Prefectura). '
          'Abrí la app para ver el dato en tiempo real.');
    });
  });

  group('migración de preferencias', () {
    Future<PreferenciasAvisos> migrar(Map<String, Object> viejas) async {
      final prefs = await prefsCon(viejas);
      await migrarPreferencias(prefs);
      expect(prefs.getKeys(), isNot(contains(claveViejaActivos)));
      expect(prefs.getKeys(), isNot(contains(claveViejaDesde)));
      expect(prefs.getInt(claveVersionAvisos), 1);
      return PreferenciasAvisos.leer(prefs);
    }

    test('instalación nueva: urgente apagado, resumen prendido', () async {
      final p = await migrar({});
      expect((p.urgente, p.desde, p.resumen), (false, Nivel.alerta, true));
      const nueva = PreferenciasAvisos();
      expect((nueva.urgente, nueva.resumen), (false, true));
    });

    test('quien tenía avisos prendidos queda con el urgente prendido', () async {
      for (final (desde, esperado) in [
        ('atencion', Nivel.alerta),
        ('alerta', Nivel.alerta),
        ('evacuacion', Nivel.evacuacion),
      ]) {
        final p = await migrar({claveViejaActivos: true, claveViejaDesde: desde});
        expect((p.urgente, p.desde, p.resumen), (true, esperado, true), reason: desde);
      }
      final sinDesde = await migrar({claveViejaActivos: true});
      expect((sinDesde.urgente, sinDesde.desde), (true, Nivel.alerta));
    });

    test('quien los tenía apagados: urgente apagado y resumen prendido', () async {
      final p = await migrar({claveViejaActivos: false, claveViejaDesde: 'evacuacion'});
      expect((p.urgente, p.desde, p.resumen), (false, Nivel.evacuacion, true));
    });

    test('se hace una sola vez: no pisa lo que se eligió después', () async {
      final prefs = await prefsCon({claveViejaActivos: true});
      await migrarPreferencias(prefs);
      await prefs.setBool(claveUrgente, false);
      await prefs.setBool(claveResumen, false);
      await prefs.setBool(claveViejaActivos, true); // como si quedara algo viejo
      await migrarPreferencias(prefs);
      final p = PreferenciasAvisos.leer(prefs);
      expect((p.urgente, p.resumen), (false, false));
    });

    test('antes de migrar, la lectura ya interpreta las viejas', () async {
      final prefs = await prefsCon({claveViejaActivos: true, claveViejaDesde: 'evacuacion'});
      final p = PreferenciasAvisos.leer(prefs);
      expect((p.urgente, p.desde, p.resumen), (true, Nivel.evacuacion, true));
    });
  });

  group('temas', () {
    test('según las preferencias, un solo tema urgente', () {
      expect(temasDeseados(const PreferenciasAvisos(), prueba: false), {'resumen-paysandu'});
      expect(temasDeseados(const PreferenciasAvisos(urgente: true), prueba: false),
          {'alerta-paysandu', 'resumen-paysandu'});
      expect(temasDeseados(const PreferenciasAvisos(urgente: true, desde: Nivel.evacuacion, resumen: false), prueba: false),
          {'evacuacion-paysandu'});
      expect(temasDeseados(const PreferenciasAvisos(resumen: false), prueba: false), isEmpty);
    });

    test('con TEMAS_PRUEBA llevan el prefijo prueba-', () {
      expect(temasDeseados(const PreferenciasAvisos(urgente: true), prueba: true),
          {'prueba-alerta-paysandu', 'prueba-resumen-paysandu'});
      expect(todosLosTemas, hasLength(6));
      expect(todosLosTemas, containsAll(['evacuacion-paysandu', 'prueba-evacuacion-paysandu']));
      // Por defecto (sin --dart-define) son los reales.
      expect(temasDePrueba, isFalse);
      expect(temasDeseados(const PreferenciasAvisos()), {'resumen-paysandu'});
    });
  });

  group('sincronizar temas', () {
    test('suscribe a los pedidos, sale de los demás y queda al día', () async {
      final prefs = await prefsCon({...todoPrendido, claveUrgenteDesde: 'evacuacion'});
      final s = SuscriptorFalso();
      expect(await sincronizarTemas(prefs, s, prueba: false), isTrue);
      expect(s.suscritos, {'evacuacion-paysandu', 'resumen-paysandu'});
      expect(s.salidas, todosLosTemas.difference({'evacuacion-paysandu', 'resumen-paysandu'}));
      expect(temasAlDia(prefs, prueba: false), isTrue);

      // Idempotente: repetir deja lo mismo.
      expect(await sincronizarTemas(prefs, s, prueba: false), isTrue);
      expect(s.estado, {'evacuacion-paysandu', 'resumen-paysandu'});

      // Al cambiar de elección se pasa al otro tema urgente.
      await prefs.setString(claveUrgenteDesde, 'alerta');
      expect(temasAlDia(prefs, prueba: false), isFalse);
      await sincronizarTemas(prefs, s, prueba: false);
      expect(s.estado, {'alerta-paysandu', 'resumen-paysandu'});
    });

    test('sin conexión queda pendiente, sin lanzar, y se reintenta después', () async {
      final prefs = await prefsCon(todoPrendido);
      final s = SuscriptorFalso()..falla = true;
      expect(await sincronizarTemas(prefs, s, prueba: false), isFalse);
      expect(temasAlDia(prefs, prueba: false), isFalse);
      s.falla = false;
      expect(await sincronizarTemas(prefs, s, prueba: false), isTrue);
      expect(temasAlDia(prefs, prueba: false), isTrue);
    });

    test('si FCM no contesta, no traba: corta por tiempo', () async {
      final prefs = await prefsCon(todoPrendido);
      final s = SuscriptorFalso()..colgado = true;
      expect(
          await sincronizarTemas(prefs, s, prueba: false, tiempoMaximo: const Duration(milliseconds: 10)), isFalse);
    });

    test('con TEMAS_PRUEBA se suscribe a los de prueba y sale de los reales', () async {
      final prefs = await prefsCon(todoPrendido);
      final s = SuscriptorFalso();
      await sincronizarTemas(prefs, s, prueba: true);
      expect(s.estado, {'prueba-alerta-paysandu', 'prueba-resumen-paysandu'});
      expect(s.salidas, containsAll(['alerta-paysandu', 'resumen-paysandu']));
    });
  });
}

class SuscriptorFalso implements Suscriptor {
  final suscritos = <String>{};
  final salidas = <String>{};
  final estado = <String>{};
  bool falla = false;
  bool colgado = false;

  Future<void> _hacer(void Function() cambio) {
    if (colgado) return Completer<void>().future;
    if (falla) return Future.error(Exception('sin conexión'));
    cambio();
    return Future.value();
  }

  @override
  Future<void> suscribir(String tema) => _hacer(() {
        suscritos.add(tema);
        estado.add(tema);
      });

  @override
  Future<void> desuscribir(String tema) => _hacer(() {
        salidas.add(tema);
        estado.remove(tema);
      });
}

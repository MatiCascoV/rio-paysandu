import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/pantallas/grafico.dart';
import 'package:rio_paysandu/textos.dart';

import 'datos_de_prueba.dart';

void main() {
  final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');

  group('lectura de los JSON', () {
    test('actual.json real', () {
      final a = Actual.desdeJson(jsonDecode(actualReal))!;
      expect(a.nivel, Nivel.alerta);
      expect(a.altura!.valorM, 5.95);
      expect(a.altura!.fecha, DateTime.parse('2026-10-09T15:00:00Z'));
      expect(a.altura!.fuente, 'CARU – estación automática Paysandú');
      expect(a.prefectura!.valorM, 5.9);
      expect(a.pronostico!.vigente, isTrue);
      expect(a.pronostico!.alturaEsperadaM, 6.66);
      expect(a.pronostico!.caudalM3s, 18000);
      expect(a.avisos, isEmpty);
    });

    test('JSON incompleto o roto no rompe ni inventa', () {
      expect(Actual.desdeJson(null), isNull);
      expect(Actual.desdeJson('hola'), isNull);
      final a = Actual.desdeJson({'altura_actual': null, 'nivel': 'cualquiera'})!;
      expect(a.altura, isNull);
      expect(a.nivel, Nivel.sinDato);
      expect(Lectura.desdeJson({'valor_m': 'abc', 'fecha': '2026-10-09T12:00:00-03:00'}), isNull);
    });

    test('umbrales con atención sin definir', () {
      final u = Umbrales.desdeJson(jsonDecode(umbralesReal))!;
      expect(u.validado, isFalse);
      expect(u.atencionM, isNull);
      expect(u.alertaM, 4.39);
      expect(u.evacuacionM, 6.89);
    });

    test('historial ordenado y sin entradas rotas', () {
      final h = PuntoHistorial.listaDesdeJson([
        {'fecha': '2026-10-09T12:00:00-03:00', 'valor_m': 5.95, 'fuente': 'estacion'},
        {'fecha': 'no es fecha', 'valor_m': 1, 'fuente': 'estacion'},
        {'fecha': '2026-10-08T06:00:00-03:00', 'valor_m': 5.6, 'fuente': 'prefectura'},
      ]);
      expect(h.map((p) => p.valorM), [5.6, 5.95]);
    });

    test('un dato de más de 48 h no da nivel', () {
      final a = Actual.desdeJson(jsonDecode(actualReal))!;
      expect(a.nivelVigente(ahora, 48), Nivel.alerta);
      expect(a.nivelVigente(ahora.add(const Duration(hours: 50)), 48), Nivel.sinDato);
    });
  });

  group('textos', () {
    test('altura con coma', () {
      expect(formatoAltura(5.9), '5,90');
      expect(formatoAltura(6.664), '6,66');
    });

    test('fecha en hora de Uruguay: hoy, ayer y otros días', () {
      expect(formatoFecha(DateTime.parse('2026-10-09T12:00:00-03:00'), ahora), 'hoy 12:00');
      expect(formatoFecha(DateTime.parse('2026-10-08T06:00:00-03:00'), ahora), 'ayer 06:00');
      expect(formatoFecha(DateTime.parse('2026-10-03T06:30:00-03:00'), ahora), '3/10 06:30');
      // 23:30 de Uruguay es el día siguiente en UTC: tiene que seguir siendo "ayer".
      expect(formatoFecha(DateTime.parse('2026-10-08T23:30:00-03:00'), ahora), 'ayer 23:30');
    });

    test('tendencia', () {
      Lectura l(String estado, double v, String p) =>
          Lectura(valorM: 5, fecha: ahora, estado: estado, variacionM: v, periodo: p);
      expect(textoTendencia(l('crece', 0.30, '24 hs')), 'Crece 30 cm en 24 h');
      expect(textoTendencia(l('crece', 0.01, '30 min')), 'Crece 1 cm en 30 min');
      expect(textoTendencia(l('baja', -0.05, '30 min')), 'Baja 5 cm en 30 min');
      expect(textoTendencia(l('estacionado', 0, '30 min')), 'Estable (sin cambios en 30 min)');
      expect(textoTendencia(Lectura(valorM: 5, fecha: ahora)), 'No se sabe si crece o baja');
    });

    test('la hora no depende de la zona del teléfono', () {
      final ahoraUtc = DateTime.utc(2026, 10, 10, 1, 30); // 22:30 del 9/10 en Uruguay
      expect(formatoFecha(DateTime.utc(2026, 10, 9, 15), ahoraUtc), 'hoy 12:00');
      expect(formatoFecha(DateTime.utc(2026, 10, 9, 2, 30), ahoraUtc), 'ayer 23:30');
      expect(formatoFecha(DateTime.utc(2025, 10, 9, 15), ahoraUtc), '9/10/2025 12:00');
    });

    test('tendencia en pasado y diferencias', () {
      final l = Lectura(valorM: 5, fecha: ahora, estado: 'crece', variacionM: 0.3, periodo: '24 hs');
      expect(textoTendencia(l, pasado: true), 'Crecía 30 cm en 24 h');
      expect(formatoDiferencia(0.94), '94 cm');
      expect(formatoDiferencia(1.19), '1,19 m');
    });

    test('frase del nivel con umbrales y cifras', () {
      const u = Umbrales(alertaM: 4.39, evacuacionM: 6.89);
      expect(descripcionNivel(Nivel.normal, u, alturaM: 3.19),
          'El río está por debajo del nivel de alerta (4,39 m). Faltan 1,20 m.');
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 6.08),
          'El río pasó el nivel de alerta (4,39 m). Faltan 81 cm para evacuación (6,89 m).');
      expect(descripcionNivel(Nivel.evacuacion, u, alturaM: 7.01),
          'El río pasó el nivel de evacuación (6,89 m) por 12 cm. La orden de evacuar la da el Cecoed. '
          'Si hay personas en peligro, llamá al 911.');
      expect(descripcionNivel(Nivel.evacuacion, u, alturaM: 6.89),
          'El río llegó al nivel de evacuación (6,89 m). La orden de evacuar la da el Cecoed. '
          'Si hay personas en peligro, llamá al 911.');
      // Con umbral de atención, ese es el siguiente; y se compara en centímetros enteros.
      const conAtencion = Umbrales(atencionM: 4.0, alertaM: 4.39, evacuacionM: 6.89);
      expect(descripcionNivel(Nivel.normal, conAtencion, alturaM: 3.99),
          'El río está por debajo del nivel de atención (4,00 m). Falta 1 cm.');
      expect(descripcionNivel(Nivel.atencion, conAtencion, alturaM: 4.2),
          'El río pasó el nivel de atención (4,00 m). Faltan 19 cm para alerta (4,39 m).');
    });

    test('frase del nivel con dato viejo, en pasado', () {
      const u = Umbrales(alertaM: 4.39, evacuacionM: 6.89);
      expect(descripcionNivel(Nivel.normal, u, alturaM: 3.19, viejo: true),
          'Con el último dato, el río estaba por debajo del nivel de alerta (4,39 m). Faltaban 1,20 m.');
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 6.08, viejo: true),
          'Con el último dato, el río estaba sobre el nivel de alerta (4,39 m). '
          'Faltaban 81 cm para evacuación (6,89 m).');
      expect(descripcionNivel(Nivel.evacuacion, u, alturaM: 7.01, viejo: true),
          'Con el último dato, el río estaba 12 cm por encima del nivel de evacuación (6,89 m). '
          'Si hay personas en peligro, llamá al 911.');
    });

    test('frase del nivel sin umbrales o sin altura: sin cifras', () {
      expect(descripcionNivel(Nivel.normal, null, alturaM: 3.19), 'El río está por debajo del nivel de alerta.');
      expect(descripcionNivel(Nivel.alerta, const Umbrales(), alturaM: 6.08), 'El río pasó el nivel de alerta.');
      expect(descripcionNivel(Nivel.alerta, const Umbrales(alertaM: 4.39)), 'El río pasó el nivel de alerta.');
      // Sin evacuación publicada, en alerta no se dice cuánto falta.
      expect(descripcionNivel(Nivel.alerta, const Umbrales(alertaM: 4.39), alturaM: 6.08),
          'El río pasó el nivel de alerta (4,39 m).');
      expect(descripcionNivel(Nivel.sinDato, const Umbrales(alertaM: 4.39), alturaM: 6.08),
          'No hay un dato reciente. Esto no quiere decir que el río esté bajo.');
    });

    test('si las cifras no cuadran con el nivel publicado, frase sin cifras', () {
      const u = Umbrales(alertaM: 4.39, evacuacionM: 6.89);
      expect(nivelSegunUmbrales(4.00, u), Nivel.normal);
      expect(nivelSegunUmbrales(4.39, u), Nivel.alerta);
      expect(nivelSegunUmbrales(7.20, u), Nivel.evacuacion);
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 4.00), 'El río pasó el nivel de alerta.');
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 7.20), 'El río pasó el nivel de alerta.');
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 4.00, viejo: true),
          'Con el último dato, el río estaba sobre el nivel de alerta.');
      expect(descripcionNivel(Nivel.normal, u, alturaM: 5.0), 'El río está por debajo del nivel de alerta.');
    });

    test('100 cm se dice en metros', () {
      expect(formatoDiferencia(4.39 - 3.39), '1,00 m');
      expect(formatoDiferencia(0.995), '1,00 m');
      expect(formatoDiferencia(0.99), '99 cm');
      expect(descripcionNivel(Nivel.normal, const Umbrales(alertaM: 4.39), alturaM: 3.39),
          'El río está por debajo del nivel de alerta (4,39 m). Faltan 1,00 m.');
    });

    test('justo en el umbral: "llegó"', () {
      const u = Umbrales(atencionM: 4.0, alertaM: 4.39, evacuacionM: 6.89);
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 4.39),
          'El río llegó al nivel de alerta (4,39 m). Faltan 2,50 m para evacuación (6,89 m).');
      expect(descripcionNivel(Nivel.atencion, u, alturaM: 4.0),
          'El río llegó al nivel de atención (4,00 m). Faltan 39 cm para alerta (4,39 m).');
      expect(descripcionNivel(Nivel.alerta, u, alturaM: 4.39, viejo: true),
          'Con el último dato, el río estaba en el nivel de alerta (4,39 m). '
          'Faltaban 2,50 m para evacuación (6,89 m).');
    });

    test('umbrales inválidos con un dato fresco', () {
      const frase = 'Hay un dato reciente, pero no se puede calcular el nivel: '
          'los niveles de referencia llegaron con un error.';
      expect(descripcionNivel(Nivel.sinDato, null, alturaM: 5.95, umbralesInvalidos: true), frase);
      // Con dato viejo o sin altura no se dice "reciente".
      expect(descripcionNivel(Nivel.sinDato, null, alturaM: 5.95, viejo: true, umbralesInvalidos: true),
          isNot(frase));
      expect(descripcionNivel(Nivel.sinDato, null, umbralesInvalidos: true), isNot(frase));
      expect(textoAviso('pronostico_no_disponible'),
          'No se pudo leer el último informe de CARU; el pronóstico puede no estar al día.');
    });

    test('unidades en palabras para el lector de pantalla', () {
      expect(unidadesEnPalabras('Pasó el nivel (6,89 m) por 12 cm. Falta 1 cm. Faltan 1,20 m.'),
          'Pasó el nivel (6,89 metros) por 12 centímetros. Falta 1 centímetro. Faltan 1,20 metros.');
    });

    test('miles', () {
      expect(formatoMiles(18000), '18.000');
      expect(formatoMiles(950), '950');
      expect(formatoMiles(1234567), '1.234.567');
    });

    test('resumen del gráfico', () {
      final puntos = [
        PuntoHistorial(DateTime.parse('2026-10-02T12:30:00-03:00'), 4.42, 'estacion'),
        PuntoHistorial(DateTime.parse('2026-10-09T12:00:00-03:00'), 5.95, 'estacion'),
      ];
      expect(resumenHistorial(puntos),
          'Del 2/10 al 9/10: de 4,42 m a 5,95 m (subió 1,53 m). Máximo: 5,95 m el 9/10.');
      expect(resumenHistorial(const []), 'No hay lecturas en este período.');
    });
  });

  // Las reglas completas de los avisos están en avisos_test.dart.
  group('cuándo avisar', () {
    test('solo al subir a alerta o evacuación, desde el mínimo elegido', () {
      expect(subidaUrgente(Nivel.normal, Nivel.alerta, Nivel.alerta), isTrue);
      expect(subidaUrgente(Nivel.alerta, Nivel.evacuacion, Nivel.alerta), isTrue);
      expect(subidaUrgente(Nivel.normal, Nivel.atencion, Nivel.alerta), isFalse);
      expect(subidaUrgente(Nivel.normal, Nivel.alerta, Nivel.evacuacion), isFalse);
      expect(subidaUrgente(Nivel.alerta, Nivel.normal, Nivel.alerta), isFalse);
      expect(subidaUrgente(null, Nivel.alerta, Nivel.alerta), isFalse);
    });

    test('mensaje', () {
      final a = Actual.desdeJson(jsonDecode(actualReal))!;
      final aviso = avisoUrgente(a, Nivel.alerta);
      expect(aviso.titulo, 'Río Uruguay: subió a ALERTA');
      expect(aviso.texto, contains('5,95 m (el 9/10 a las 12:00)'));
      expect(aviso.texto, contains('Fuente: CARU'));
      expect(avisoUrgente(a, Nivel.evacuacion).titulo, 'Río Uruguay: subió a EVACUACIÓN');
    });
  });
}

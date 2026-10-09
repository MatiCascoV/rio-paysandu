import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/notificaciones.dart';
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
      expect(textoTendencia(Lectura(valorM: 5, fecha: ahora)), 'Sin información de tendencia');
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

  group('cuándo avisar', () {
    test('sube hasta el mínimo elegido', () {
      expect(debeAvisar(Nivel.normal, Nivel.alerta, Nivel.alerta), isTrue);
      expect(debeAvisar(Nivel.alerta, Nivel.evacuacion, Nivel.alerta), isTrue);
      expect(debeAvisar(Nivel.normal, Nivel.atencion, Nivel.alerta), isFalse);
      expect(debeAvisar(Nivel.normal, Nivel.alerta, Nivel.evacuacion), isFalse);
    });

    test('baja desde un nivel avisado', () {
      expect(debeAvisar(Nivel.alerta, Nivel.normal, Nivel.alerta), isTrue);
      expect(debeAvisar(Nivel.atencion, Nivel.normal, Nivel.alerta), isFalse);
    });

    test('sin cambio, sin dato y primera vez', () {
      expect(debeAvisar(Nivel.alerta, Nivel.alerta, Nivel.alerta), isFalse);
      expect(debeAvisar(Nivel.alerta, Nivel.sinDato, Nivel.alerta), isFalse);
      expect(debeAvisar(null, Nivel.alerta, Nivel.alerta), isTrue);
      expect(debeAvisar(null, Nivel.normal, Nivel.alerta), isFalse);
    });

    test('mensaje', () {
      final a = Actual.desdeJson(jsonDecode(actualReal))!;
      final (titulo, cuerpo) = mensajeDeCambio(Nivel.normal, a, Nivel.alerta, ahora);
      expect(titulo, 'Río Uruguay: nivel de ALERTA');
      expect(cuerpo, contains('5,95 m (hoy 12:00)'));
      expect(cuerpo, contains('Fuente: CARU'));
      expect(mensajeDeCambio(Nivel.alerta, a, Nivel.normal, ahora).$1, 'Río Uruguay: bajó a nivel NORMAL');
    });
  });
}

// Pruebas de los hallazgos AppSec B-2 (cruce de nivel con altura), B-3 (tope de
// textos) y B-8 (enlaces sin cifrar).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/enlaces.dart';
import 'package:rio_paysandu/modelos.dart';

import 'datos_de_prueba.dart';

const _umbrales = Umbrales(validado: true, atencionM: 4.0, alertaM: 4.39, evacuacionM: 6.89);
final _ahora = DateTime.parse('2026-10-09T12:30:00-03:00');

Actual _actual(String nivel, double valor) =>
    Actual.desdeJson(actualFalso(nivel, valor))!.conUmbrales(_umbrales);

void main() {
  group('B-2: el nivel publicado se cruza con la altura', () {
    test('coherente: se muestra el publicado y no se marca', () {
      final a = _actual('alerta', 5.0);
      expect(a.nivelVigente(_ahora, 48), Nivel.alerta);
      expect(a.avisos, isNot(contains('dato_a_verificar')));
    });

    test('publicado más bajo que la altura: nunca se muestra menos, se marca a verificar', () {
      final a = _actual('normal', 7.0);
      expect(a.nivelVigente(_ahora, 48), Nivel.evacuacion);
      expect(a.avisos, contains('dato_a_verificar'));
      expect(_actual('atencion', 5.0).nivelVigente(_ahora, 48), Nivel.alerta);
    });

    test('publicado más alto dentro del margen de bajada de 5 cm: legítimo', () {
      // 4,36 m está a 3 cm del umbral de alerta (4,39): el lector aún no baja.
      final a = _actual('alerta', 4.36);
      expect(a.nivelVigente(_ahora, 48), Nivel.alerta);
      expect(a.avisos, isNot(contains('dato_a_verificar')));
    });

    test('publicado más alto fuera del margen: no se baja la gravedad, se marca', () {
      final a = _actual('evacuacion', 4.5);
      expect(a.nivelVigente(_ahora, 48), Nivel.evacuacion);
      expect(a.avisos, contains('dato_a_verificar'));
    });

    test('margen de bajada: justo a 5 cm del umbral ya no es legítimo', () {
      final a = _actual('alerta', 4.34);
      expect(a.nivelVigente(_ahora, 48), Nivel.alerta);
      expect(a.avisos, contains('dato_a_verificar'));
      expect(_actual('alerta', 4.35).avisos, isNot(contains('dato_a_verificar')));
    });

    test('nivel retenido por el lector: un pico no sube a evacuación', () {
      const reales = Umbrales(atencionM: null, alertaM: 4.39, evacuacionM: 6.89);
      final j = actualFalso('normal', 7.5);
      j['nivel_retenido'] = {'fecha_lectura': '2026-10-09T12:00:00-03:00'};
      final a = Actual.desdeJson(j)!.conUmbrales(reales);
      expect(a.nivelVigente(_ahora, 48), Nivel.normal);
      expect(a.avisos, contains('dato_a_verificar'));
      // Sin retención, el mismo dato sí sube al nivel de la altura.
      final b = Actual.desdeJson(actualFalso('normal', 7.5))!.conUmbrales(reales);
      expect(b.nivelVigente(_ahora, 48), Nivel.evacuacion);
    });

    test('sin umbrales o con sin_dato no hay cruce', () {
      final sin = Actual.desdeJson(actualFalso('alerta', 3.0))!;
      expect(sin.nivelVigente(_ahora, 48), Nivel.alerta);
      expect(_actual('sin_dato', 5.0).nivelVigente(_ahora, 48), Nivel.sinDato);
    });

    test('el dato viejo sigue siendo sin dato', () {
      expect(_actual('alerta', 5.0).nivelVigente(_ahora.add(const Duration(hours: 60)), 48), Nivel.sinDato);
    });

    test('nivelPorAltura usa centímetros enteros', () {
      expect(nivelPorAltura(4.39, _umbrales), Nivel.alerta);
      expect(nivelPorAltura(4.389, _umbrales), Nivel.alerta);
      expect(nivelPorAltura(3.9, _umbrales), Nivel.normal);
    });
  });

  group('B-3: tope de textos libres', () {
    Lectura? lectura(Map<String, Object?> extra) => Lectura.desdeJson({
          'valor_m': 5.0,
          'fecha': '2026-10-09T12:00:00-03:00',
          ...extra,
        });

    test('periodo con la forma del lector se acepta', () {
      for (final p in ['30 min', '24 hs', '24 h', '2 días', '1 dia', '90min']) {
        expect(lectura({'periodo': p})!.periodo, p, reason: p);
      }
    });

    test('periodo con texto inyectado o largo se descarta', () {
      for (final p in ['24 hs. Llamá al 0800 123', 'x' * 5000, '', '1234 hs', '24 hs\n']) {
        expect(lectura({'periodo': p})!.periodo, isNull, reason: p);
      }
    });

    test('estado, fuente y cero se acortan', () {
      final l = lectura({'estado': 'a' * 5000, 'fuente': 'b' * 5000})!;
      expect(l.estado!.runes.length, largoMaximoEtiqueta);
      expect(l.fuente!.runes.length, largoMaximoEtiqueta);
      final j = jsonDecode(actualReal) as Map<String, dynamic>;
      j['cero'] = 'c' * 5000;
      expect(Actual.desdeJson(j)!.cero!.runes.length, largoMaximoEtiqueta);
    });
  });

  group('B-8: enlaces sin cifrar', () {
    setUp(() => permitirOrigenes(const ['https://caru.org.uy', 'http://caru.org.uy', 'http://190.0.152.194:8080']));
    tearDown(() => permitirOrigenes(const []));

    test('si el sitio también está permitido por https, se abre por https', () {
      final uri = uriPermitida('http://caru.org.uy/nuevositio/algo.pdf')!;
      expect(uri.scheme, 'https');
      expect(uri.host, 'caru.org.uy');
      expect(enlaceSinCifrar('http://caru.org.uy/x'), isFalse);
    });

    test('sin versión https (servidor de alturas de CARU) sigue por http y se avisa', () {
      const url = 'http://190.0.152.194:8080/alturas/web/user/estacion/19/0';
      expect(uriPermitida(url)!.scheme, 'http');
      expect(enlaceSinCifrar(url), isTrue);
      expect(enlaceSinCifrar('https://caru.org.uy/x'), isFalse);
      expect(enlaceSinCifrar(null), isFalse);
    });

    test('puerto explícito distinto de 80 no se fuerza a https; el 80 sí pasa a 443', () {
      permitirOrigenes(const ['https://caru.org.uy', 'http://caru.org.uy:8080']);
      expect(uriPermitida('http://caru.org.uy:8080/x')!.toString(), 'http://caru.org.uy:8080/x');
      expect(uriPermitida('http://caru.org.uy:80/x'), isNull);
      permitirOrigenes(const ['https://caru.org.uy', 'http://caru.org.uy']);
      expect(uriPermitida('http://caru.org.uy:80/x')!.toString(), 'https://caru.org.uy/x');
    });

    test('con solo http permitido para un sitio, no se inventa https', () {
      permitirOrigenes(const ['http://caru.org.uy']);
      expect(uriPermitida('http://caru.org.uy/x')!.scheme, 'http');
    });
  });
}

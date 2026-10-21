import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';
import 'package:rio_paysandu/mapa/logica_mapa.dart';
import 'package:rio_paysandu/mapa/modelos_mapa.dart';
import 'package:rio_paysandu/mapa/repositorio_mapa.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/mapa.dart';

import 'datos_de_prueba.dart';
import 'fixtures_mapa.dart';

IndiceMapa indiceCon([void Function(Map<String, dynamic>)? cambio]) {
  final j = indiceDePrueba();
  cambio?.call(j);
  return IndiceMapa.desdeJson(j);
}

Matcher rechazaPor(String parte) => throwsA(isA<ErrorMapa>().having((e) => e.motivo, 'motivo', contains(parte)));

void main() {
  group('redondeo hacia arriba a 10 cm', () {
    test('casos', () {
      expect(redondearArriba(5.63), 570);
      expect(redondearArriba(5.70), 570);
      expect(redondearArriba(5.61), 570);
      expect(redondearArriba(5.69), 570);
      expect(redondearArriba(5.71), 580);
      expect(redondearArriba(5.6999999), 570); // sin errores de coma flotante
      expect(redondearArriba(0), 0);
      expect(redondearArriba(10.5), 1050);
      expect(redondearArriba(5.63, pasoCm: 25), 575);
    });
  });

  group('elección de capa', () {
    final ind = indiceCon(); // 4,00 a 4,30 m, margen 20 cm

    test('dentro del rango: la capa y el margen', () {
      final e = elegirAgua(410, ind);
      expect(e.situacion, SituacionAgua.enRango);
      expect(e.capaCm, 410);
      expect(e.margenCm, 430);
    });

    test('el margen no pasa del máximo: ahí coincide con la capa máxima, pero se dibuja igual', () {
      expect(elegirAgua(420, ind).margenCm, 430);
      expect(elegirAgua(430, ind).margenCm, 430);
    });

    test('debajo del mínimo: el agua no pasa de la zona baja; la zona baja y el margen se dibujan igual', () {
      final e = elegirAgua(390, ind);
      expect(e.situacion, SituacionAgua.debajoDelMinimo);
      expect(e.capaCm, isNull);
      expect(e.margenCm, 410);
      expect(e.zonaBajaCm, 400);
      expect(e.noPasaDeLaZonaBaja, isTrue);
      // muy por debajo: el margen queda en la capa más baja, nunca falta
      expect(elegirAgua(300, ind).margenCm, 400);
      expect(elegirAgua(300, ind).zonaBajaCm, 400);
    });

    test('en el mínimo se dice lo mismo que justo debajo (sin salto de texto)', () {
      expect(elegirAgua(400, ind).noPasaDeLaZonaBaja, isTrue);
      expect(elegirAgua(400, ind).capaCm, 400);
      expect(elegirAgua(410, ind).noPasaDeLaZonaBaja, isFalse);
    });

    test('encima del máximo: la capa más alta, con el margen en la máxima', () {
      final e = elegirAgua(900, ind);
      expect(e.situacion, SituacionAgua.sobreMaximo);
      expect(e.capaCm, 430);
      expect(e.margenCm, 430);
      expect(e.zonaBajaCm, 400);
    });
  });

  group('validación del índice', () {
    test('el set de prueba es válido', () {
      final ind = indiceCon();
      expect(ind.cero, 'Local');
      expect(ind.minCm, 400);
      expect(ind.maxCm, 430);
      expect(ind.pasoCm, 10);
      expect(ind.margenCm, 20);
      expect(ind.capas.map((c) => c.alturaCm), alturasDePrueba);
      expect(ind.referencias, hasLength(1)); // la rota se saltea
      expect(ind.modelo.esProvisorio, isFalse);
    });

    test('rechaza lo que no cuadra', () {
      expect(() => indiceCon((j) => j.remove('cero')), rechazaPor('cero'));
      expect(() => indiceCon((j) => j['version'] = 0), rechazaPor('version'));
      expect(
        () => indiceCon((j) => (j['capas'] as List).insert(0, (j['capas'] as List).removeAt(1))),
        rechazaPor('orden'),
      );
      expect(() => indiceCon((j) => (j['capas'] as List).removeAt(2)), rechazaPor('capas'));
      expect(() => indiceCon((j) => j['paso_m'] = 0.20), rechazaPor('paso'));
      expect(() => indiceCon((j) => j['paso_m'] = 0), rechazaPor('paso_m'));
      expect(() => indiceCon((j) => j['min_m'] = 4.5), rechazaPor('min_m'));
      expect(() => indiceCon((j) => j['max_m'] = 25), rechazaPor('max_m'));
      expect(() => indiceCon((j) => (j['capas'] as List)[1]['archivo'] = 'agua/0999.json'), rechazaPor('0410'));
      expect(() => indiceCon((j) => (j['capas'] as List)[1]['sha256'] = 'abc'), rechazaPor('sha256'));
      expect(() => indiceCon((j) => (j['capas'] as List)[1]['bytes'] = TopesMapa.bytesCapa + 1), rechazaPor('bytes'));
      expect(() => indiceCon((j) => j['base']['archivo'] = '../secreto.json'), rechazaPor('archivo'));
      expect(() => indiceCon((j) => j['base']['archivo'] = '/base.json'), rechazaPor('archivo'));
      expect(
        () => indiceCon(
          (j) => j['limites'] = [
            [10, 10],
            [11, 11],
          ],
        ),
        rechazaPor('limites'),
      );
      expect(
        () => indiceCon(
          (j) => j['limites'] = [
            [-32.3, -58.0],
            [-32.4, -58.1],
          ],
        ),
        rechazaPor('limites'),
      ); // al revés
      expect(() => indiceCon((j) => j['modelo']['margen_m'] = 5), rechazaPor('margen'));
      expect(() => indiceCon((j) => j.remove('modelo')), rechazaPor('modelo'));
      expect(() => IndiceMapa.desdeJson([1, 2]), rechazaPor('objeto'));
    });

    test('tope de bytes totales', () {
      expect(
        () => indiceCon(
          (j) => (j['referencias'] as List).add({
            'tipo': 'crecida',
            'nombre': 'X',
            'altura_m': 5,
            'bytes': TopesMapa.bytesTotales,
          }),
        ),
        rechazaPor('demasiados bytes'),
      );
    });

    test('PROVISORIO se reconoce', () {
      expect(indiceCon((j) => j['modelo']['metodo'] = 'PROVISORIO: inventado').modelo.esProvisorio, isTrue);
    });
  });

  group('GeoJSON', () {
    final ind = indiceCon();
    final capa410 = ind.capaDe(410)!;

    test('capa con huecos y capa vacía', () {
      final c = CapaAgua.desdeJson(capaDePrueba(410), capa410, ind);
      expect(c.poligonos, hasLength(1));
      expect(c.poligonos.first.huecos, hasLength(1));
      expect(CapaAgua.desdeJson(capaDePrueba(400), ind.capaDe(400)!, ind).vacia, isTrue);
    });

    test('la altura de la capa tiene que coincidir con el índice', () {
      expect(() => CapaAgua.desdeJson(capaDePrueba(420), capa410, ind), rechazaPor('altura_m'));
    });

    test('coordenadas fuera del mapa o que no son números', () {
      Map<String, dynamic> con(List<Object> punto) {
        final c = jsonDecode(jsonEncode(capaDePrueba(410))) as Map<String, dynamic>; // listas sin tipo, como en un JSON
        final anillo =
            (((((c['features'] as List).first as Map)['geometry'] as Map)['coordinates'] as List).first as List).first
                as List;
        anillo[1] = punto;
        return c;
      }

      expect(() => CapaAgua.desdeJson(con([-60.0, -32.35]), capa410, ind), rechazaPor('fuera'));
      expect(() => CapaAgua.desdeJson(con(['x', -32.35]), capa410, ind), throwsA(isA<ErrorMapa>()));
    });

    test('un anillo sin cerrar se cierra; Polygon también sirve', () {
      final c = capaDePrueba(410);
      final f = (c['features'] as List).first as Map;
      f['geometry'] = {
        'type': 'Polygon',
        'coordinates': [
          [
            [-58.09, -32.39],
            [-58.08, -32.39],
            [-58.08, -32.31],
          ],
        ],
      };
      final capa = CapaAgua.desdeJson(c, capa410, ind);
      expect(capa.poligonos.single.exterior, hasLength(4));
      expect(capa.poligonos.single.exterior.first, capa.poligonos.single.exterior.last);
    });

    test('fondo: agua, arroyo, calles por clase y barrios', () {
      final b = BaseMapa.desdeJson(baseDePrueba(), ind);
      expect(b.agua, hasLength(1));
      expect(b.cursos.single.nombre, 'Arroyo de Prueba');
      expect(b.calles.map((c) => c.clase), [1, 2, 3, 3]);
      expect(b.calles.last.nombre, isNull);
      expect(b.lugares.map((l) => l.nombre), ['Barrio Norte', 'Barrio Sur']);
    });
  });

  group('repositorio', () {
    test('lee índice, fondo y capas', () async {
      final r = RepositorioMapa(fuenteDePrueba());
      expect(await r.indice(), isA<IndiceListo>());
      expect(await r.base(), isNotNull);
      final c = await r.capa(420);
      expect(c!.alturaCm, 420);
      expect(c.reemplazada, isFalse);
    });

    test('sin archivos: no disponible, sin romper', () async {
      final r = RepositorioMapa(FuenteMemoria({}));
      final e = await r.indice();
      expect(e, isA<IndiceNoDisponible>());
      expect(await r.base(), isNull);
      expect(await r.capa(420), isNull);
    });

    test('índice que no es JSON o no valida', () async {
      final roto = RepositorioMapa(FuenteMemoria({'indice.json': Uint8List.fromList(utf8.encode('<html>'))}));
      expect(await roto.indice(), isA<IndiceNoDisponible>());
      final malo = RepositorioMapa(fuenteDePrueba(indice: (j) => j['cero'] = ''));
      expect(((await malo.indice()) as IndiceNoDisponible).motivo, contains('cero'));
    });

    test('una capa con la huella cambiada se descarta y se usa la de arriba', () async {
      final r = RepositorioMapa(fuenteDePrueba(archivos: {'agua/0420.json': jsonABytes(capaDePrueba(430))}));
      final c = await r.capa(420);
      expect(c!.alturaCm, 430);
      expect(c.reemplazada, isTrue);
      expect(c.pedidaCm, 420);
    });

    test('si no queda ninguna capa por encima, null (nunca una de abajo)', () async {
      final r = RepositorioMapa(fuenteDePrueba(archivos: {'agua/0430.json': null}));
      expect(await r.capa(430), isNull);
      expect((await r.capa(420))!.alturaCm, 420);
    });

    test('fondo con la huella cambiada: no hay fondo', () async {
      final r = RepositorioMapa(
        fuenteDePrueba(
          archivos: {
            'base.json': jsonABytes({'type': 'FeatureCollection'}),
          },
        ),
      );
      expect(await r.base(), isNull);
    });

    test('un archivo más grande que el tope no se lee', () async {
      final grande = Uint8List(TopesMapa.bytesIndice + 1);
      final r = RepositorioMapa(FuenteMemoria({'indice.json': grande}));
      expect(await r.indice(), isA<IndiceNoDisponible>());
    });

    test('caché: una capa leída no se vuelve a leer; guarda las últimas', () async {
      final f = fuenteDePrueba();
      final r = RepositorioMapa(f, capasEnMemoria: 2);
      await r.capa(410);
      await r.capa(410);
      expect(f.lecturas['agua/0410.json'], 1);
      await r.capa(420);
      await r.capa(410); // pasa a ser la más reciente
      await r.capa(430); // sale la 420, la menos usada
      expect(r.capasGuardadas, [410, 430]);
      await r.capa(420);
      expect(f.lecturas['agua/0420.json'], 2);
      // el índice se lee una sola vez
      expect(f.lecturas['indice.json'], 1);
    });

    test('una capa rota no se vuelve a intentar', () async {
      final f = fuenteDePrueba(archivos: {'agua/0420.json': Uint8List.fromList(utf8.encode('{'))});
      final r = RepositorioMapa(f);
      await r.capa(420);
      await r.capa(420);
      expect(f.lecturas['agua/0420.json'], 1);
    });
  });

  group('datos reales: rango 4,00–10,50, curvas y validado', () {
    test('el índice del rango del contrato valida con 66 capas', () {
      final ind = IndiceMapa.desdeJson(indiceDePrueba(desde: 400, hasta: 1050));
      expect(ind.capas, hasLength(66));
      expect(ind.capaDe(1050)!.archivo, 'agua/1050.json');
      expect(ind.validado, isFalse);
      expect(ind.cero, ceroDelMapa);
    });

    test('elección en el rango real: redondeo, cauce, máximo y margen de 50 cm', () {
      final ind = IndiceMapa.desdeJson(
        indiceDePrueba(desde: 400, hasta: 1050)..['modelo'] = {'metodo': 'x', 'margen_m': 0.5},
      );
      expect(elegirAgua(redondearArriba(6.73), ind).capaCm, 680);
      expect(elegirAgua(redondearArriba(6.73), ind).margenCm, 730);
      // 3,95 sube a 4,00: se pinta la capa más baja (más agua, no menos)
      expect(elegirAgua(redondearArriba(3.95), ind).situacion, SituacionAgua.enRango);
      expect(elegirAgua(redondearArriba(3.85), ind).situacion, SituacionAgua.debajoDelMinimo);
      expect(elegirAgua(redondearArriba(3.85), ind).margenCm, 440); // los puntos igual se ven
      final arriba = elegirAgua(redondearArriba(10.83), ind);
      expect(arriba.situacion, SituacionAgua.sobreMaximo);
      expect(arriba.capaCm, 1050);
      expect(elegirAgua(1030, ind).margenCm, 1050); // el margen no pasa del máximo
    });

    test('referencia con curva: se lee el archivo; si está mal, queda sin contorno', () {
      final ind = indiceCon();
      final ref = ind.referencias.single;
      expect(ref.nombre, 'Crecida de prueba');
      expect(ref.alturaCm, 425);
      expect(ref.archivo!.archivo, 'curvas/2015-12.json');
      Map<String, dynamic> conRef(void Function(Map r) cambio) {
        final j = indiceDePrueba();
        cambio((j['referencias'] as List).first as Map);
        return j;
      }

      for (final cambio in <void Function(Map)>[
        (r) => r['sha256'] = 'abc',
        (r) => r['bytes'] = 0, // como el ejemplo del contrato
        (r) => r['archivo'] = 'agua/0420.json', // las curvas van en curvas/
        (r) => r['archivo'] = '../curvas/x.json',
      ]) {
        final i = IndiceMapa.desdeJson(conRef(cambio));
        expect(i.referencias.single.archivo, isNull);
        expect(i.referencias.single.alturaM, 4.25);
      }
    });

    test('las referencias se ordenan por altura', () {
      final ind = indiceCon(
        (j) => (j['referencias'] as List).insert(0, {'tipo': 'crecida', 'nombre': 'Más alta', 'altura_m': 9.12}),
      );
      expect(ind.referencias.map((r) => r.nombre), ['Crecida de prueba', 'Más alta']);
    });

    test('curva: valida forma y altura', () {
      final ind = indiceCon();
      final ref = ind.referencias.single;
      expect(CurvaMapa.desdeJson(curvaDePrueba(), ref, ind).poligonos, hasLength(1));
      expect(() => CurvaMapa.desdeJson(curvaDePrueba(altura: 8.35), ref, ind), rechazaPor('altura_m'));
      expect(
        () => CurvaMapa.desdeJson({'type': 'FeatureCollection', 'features': []}, ref, ind),
        rechazaPor('Features'),
      );
    });

    test('repositorio: curva verificada, guardada, y null si la huella no coincide', () async {
      final f = fuenteDePrueba();
      final r = RepositorioMapa(f);
      final ref = ((await r.indice()) as IndiceListo).indice.referencias.single;
      expect(await r.curva(ref), isNotNull);
      await r.curva(ref);
      expect(f.lecturas['curvas/2015-12.json'], 1);
      final roto = RepositorioMapa(
        fuenteDePrueba(archivos: {'curvas/2015-12.json': jsonABytes(curvaDePrueba(nombre: 'cambiada'))}),
      );
      expect(await roto.curva(ref), isNull);
      expect(await roto.capa(420), isNotNull); // lo demás sigue
    });

    test('en segundo plano (compute, otro isolate de verdad) arma lo mismo', () async {
      // Capas grandes para pasar el umbral del segundo plano.
      final grande = <String, dynamic>{
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'altura_m': 4.2},
            'geometry': {
              'type': 'MultiPolygon',
              'coordinates': [
                for (var k = 0; k < 400; k++)
                  [
                    [
                      for (var i = 0; i < 20; i++) [-58.09 + i * 0.0001, -32.39 + k * 0.0002],
                      [-58.09, -32.39 + k * 0.0002],
                    ],
                  ],
              ],
            },
          },
        ],
      };
      final bytes = jsonABytes(grande);
      expect(bytes.length, greaterThan(96 * 1024));
      final fuente = fuenteDePrueba(
        indice: (j) {
          final c = (j['capas'] as List)[2] as Map;
          c['bytes'] = bytes.length;
          c['sha256'] = sha256.convert(bytes).toString();
        },
        archivos: {'agua/0420.json': bytes},
      );
      final r = RepositorioMapa(fuente, enSegundoPlano: true);
      final capa = await r.capa(420);
      expect(capa!.alturaCm, 420);
      expect(capa.reemplazada, isFalse);
      expect(capa.capa.poligonos, hasLength(400));
      expect(await r.base(), isNotNull);
      final ref = ((await r.indice()) as IndiceListo).indice.referencias.single;
      expect(await r.curva(ref), isNotNull);
      // y una huella rota en segundo plano también se descarta
      final mala = RepositorioMapa(fuenteDePrueba(archivos: {'agua/0420.json': bytes}), enSegundoPlano: true);
      expect((await mala.capa(420))!.alturaCm, 430);
    });
  });

  group('altura de hoy para el mapa', () {
    final ind = indiceCon();
    const config = Config(urlBase: 'https://ejemplo.test/data/');
    final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');
    Datos datos(Map<String, dynamic> j, {bool sinConexion = false}) =>
        Datos(actual: Actual.desdeJson(j), sinConexion: sinConexion);

    test('dato fresco', () {
      final h = hoyParaMapa(datos(actualFalso('alerta', 5.95)), config, ind, ahora);
      expect(h.hay, isTrue);
      expect(h.nivel, Nivel.alerta);
      expect(h.viejo, isFalse);
    });

    test('dato viejo, sin conexión y vencido', () {
      final d = datos(actualFalso('alerta', 5.95), sinConexion: true);
      final viejo = hoyParaMapa(d, config, ind, ahora.add(const Duration(hours: 8)));
      expect(viejo.hay && viejo.viejo && viejo.sinConexion, isTrue);
      final vencido = hoyParaMapa(d, config, ind, ahora.add(const Duration(hours: 60)));
      expect(vencido.hay, isFalse);
      expect(vencido.motivo, 'sin_dato');
    });

    test('sin nivel calculado pero con una altura fresca: igual se pinta', () {
      final h = hoyParaMapa(datos(actualFalso('sin_dato', 5.95)), config, ind, ahora);
      expect(h.hay, isTrue);
      expect(h.nivel, Nivel.sinDato);
    });

    test('el cero de actual.json tiene que ser el del mapa', () {
      final j = actualFalso('alerta', 5.95)..['cero'] = 'Oficial';
      expect(hoyParaMapa(datos(j), config, ind, ahora).motivo, 'cero');
      final sinCero = actualFalso('alerta', 5.95)..remove('cero');
      expect(hoyParaMapa(datos(sinCero), config, ind, ahora).motivo, 'cero');
    });

    test('sin datos', () {
      expect(hoyParaMapa(null, config, ind, ahora).motivo, 'sin_dato');
      expect(hoyParaMapa(datos(actualFalso('sin_dato', null)), config, ind, ahora).motivo, 'sin_dato');
    });
  });

  // El mismo control que haría el CI: los archivos que van en el APK pasan la
  // validación de la app y usan el cero de actual.json.
  test('assets/mapa/ es válido', () async {
    final carpeta = Directory('assets/mapa');
    if (!carpeta.existsSync()) return; // sin mapa empaquetado, la pestaña lo dice
    final archivos = <String, Uint8List>{
      for (final f in carpeta.listSync(recursive: true).whereType<File>())
        f.path.substring(carpeta.path.length + 1).replaceAll(r'\', '/'): f.readAsBytesSync(),
    };
    final r = RepositorioMapa(FuenteMemoria(archivos));
    final e = await r.indice();
    expect(e, isA<IndiceListo>(), reason: e is IndiceNoDisponible ? e.motivo : null);
    final ind = (e as IndiceListo).indice;
    expect(ind.cero, Actual.desdeJson(jsonDecode(actualReal))!.cero);
    expect(await r.base(), isNotNull);
    for (final c in ind.capas) {
      final capa = await r.capa(c.alturaCm);
      expect(capa?.reemplazada, isFalse, reason: 'capa ${c.archivo}');
    }
    for (final ref in ind.referencias) {
      if (ref.archivo == null) continue;
      expect(await r.curva(ref), isNotNull, reason: 'curva ${ref.archivo!.archivo}');
    }
  });

  // pubspec.yaml no busca en subcarpetas: cada carpeta con archivos del mapa
  // tiene que estar declarada, o el archivo no entra en el APK y la capa se
  // pierde sin aviso (la app usaría la de arriba).
  test('pubspec.yaml declara todas las carpetas de assets/mapa/', () {
    final carpeta = Directory('assets/mapa');
    if (!carpeta.existsSync()) return;
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declaradas = RegExp(
      r'^\s*-\s*(assets/\S+/)\s*$',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m.group(1)).toSet();
    final carpetas = [
      carpeta,
      ...carpeta.listSync(recursive: true).whereType<Directory>(),
    ].map((d) => '${d.path.replaceAll(r'\', '/')}/');
    for (final c in carpetas) {
      expect(declaradas, contains(c), reason: 'falta "- $c" en pubspec.yaml');
    }
    expect(declaradas, contains('assets/mapa/curvas/'));
  });
}

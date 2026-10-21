/// Hallazgos de la revisión de código de la rama `mapa-inundacion` (parte
/// app): margen recortado en el máximo (I1), capa de agua ilegible (I2), zona
/// baja que no valida (M1), índice con versión, mínimo o margen raros (M2/M3),
/// redondeo hacia arriba de las alturas (M9), licencias de datos (M8) y la
/// fila de la línea de hoy en la leyenda. B1 está en mapa_v11_test.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/mapa/estilo_mapa.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';
import 'package:rio_paysandu/mapa/logica_mapa.dart';
import 'package:rio_paysandu/mapa/modelos_mapa.dart';
import 'package:rio_paysandu/mapa/repositorio_mapa.dart';
import 'package:rio_paysandu/pantallas/mapa.dart';

import 'fixtures_mapa.dart';
import 'mapa_test.dart' show datosCon, lectura, mostrarMapa;

/// El rango real (4,00 a 10,50 m) con el margen real de 50 cm.
FuenteMemoria fuenteReal({Map<String, List<int>?> archivos = const {}}) => fuenteDePrueba(
  desde: 400,
  hasta: 1050,
  zonaBaja: true,
  indice: (j) => (j['modelo'] as Map)['margen_m'] = 0.5,
  archivos: {for (final MapEntry(:key, :value) in archivos.entries) key: value == null ? null : jsonABytes(value)},
);

/// Una capa que no pasa la huella (sha256 distinto del índice).
const List<int> capaRota = [1, 2, 3];

IndiceMapa indiceReal() => IndiceMapa.desdeJson(jsonDecode(utf8.decode(fuenteReal().archivos['indice.json']!)));

/// La línea de la lectura con [texto] lleva el ícono de aviso.
bool lineaConAviso(WidgetTester t, String texto) {
  final fila = find.ancestor(
    of: find.descendant(of: find.byType(LecturaMapa), matching: find.text(texto)),
    matching: find.byType(Row),
  );
  if (fila.evaluate().isEmpty) return false;
  return find.descendant(of: fila.first, matching: find.byIcon(Icons.warning_amber)).evaluate().isNotEmpty;
}

/// La descripción del mapa para TalkBack (el resumen).
String resumenEnPantalla(WidgetTester t) {
  final nodo = find.bySemanticsLabel(RegExp('^Mapa de la costa de Paysandú'));
  return t.getSemantics(nodo).label;
}

Matcher rechazaPor(String parte) => throwsA(isA<ErrorMapa>().having((e) => e.motivo, 'motivo', contains(parte)));

void main() {
  group('I1: margen recortado en el máximo del mapa', () {
    final ind = indiceReal();

    test('la elección lo marca solo cuando altura + margen pasa del máximo', () {
      expect(elegirAgua(1000, ind).margenRecortado, isFalse); // 10,00 + 0,50 = 10,50: entra justo
      expect(elegirAgua(1030, ind).margenRecortado, isTrue);
      expect(elegirAgua(1030, ind).margenCm, 1050);
      expect(elegirAgua(1050, ind).margenRecortado, isTrue);
      expect(elegirAgua(1050, ind).margenCm, 1050); // franja de ancho 0
      expect(elegirAgua(1120, ind).margenRecortado, isTrue); // sobre el máximo (tiene su propio aviso)
      expect(elegirAgua(700, ind).margenRecortado, isFalse);
      expect(elegirAgua(350, ind).margenRecortado, isFalse);
    });

    for (final (altura, texto) in [(10.25, '10,30'), (10.50, '10,50')]) {
      testWidgets('con $texto m: aviso en la lectura, leyenda y resumen sin "+50 cm"', (t) async {
        final s = t.ensureSemantics();
        await mostrarMapa(t, datosCon(altura, nivel: 'evacuacion'), fuente: fuenteReal());
        expect(lectura(texto), findsOneWidget);
        final aviso = textoMargenRecortado(1050);
        expect(
          aviso,
          'El mapa llega hasta 10,50 m: con un poco más de altura, el agua puede pasar los puntos y '
          'llegar más lejos de lo que se ve.',
        );
        expect(find.descendant(of: find.byType(LecturaMapa), matching: find.text(aviso)), findsOneWidget);
        expect(lineaConAviso(t, aviso), isTrue, reason: 'la línea va con aviso: true');
        // Leyenda: no promete "hasta 50 cm más" cuando los puntos se cortan.
        expect(find.text('${textoLeyendaMargenRecortado(1050)} (borde de puntos)'), findsOneWidget);
        expect(find.textContaining(textoLeyendaMargen(50)), findsNothing);
        // Resumen: lo mismo, con las unidades en palabras.
        expect(
          resumenEnPantalla(t),
          contains('El mapa llega hasta 10,50 metros: con un poco más de altura, el agua puede pasar los puntos'),
        );
        s.dispose();
      });
    }

    testWidgets('con 10,00 m el margen entra entero: sin aviso y la leyenda dice 50 cm', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(10.0, nivel: 'evacuacion'), fuente: fuenteReal());
      expect(lectura('10,00'), findsOneWidget);
      expect(find.text(textoMargenRecortado(1050)), findsNothing);
      expect(find.text('${textoLeyendaMargen(50)} (borde de puntos)'), findsOneWidget);
      expect(textoLeyendaMargen(50), 'Puede llegar un poco más: hasta 50 cm más de altura');
      expect(resumenEnPantalla(t), isNot(contains('pasar los puntos')));
      s.dispose();
    });

    test('resumenMapa: el recorte se dice en rango y no se repite sobre el máximo', () {
      final enRango = resumenMapa(
        situacion: SituacionAgua.enRango,
        alturaCm: 1050,
        dibujoCm: 1050,
        margenCm: 1050,
        minCm: 400,
        maxCm: 1050,
        margenRecortado: true,
      );
      expect(enRango, contains('El mapa llega hasta 10,50 metros: con un poco más de altura'));
      expect(enRango, isNot(contains(' m ')));
      final sobre = resumenMapa(
        situacion: SituacionAgua.sobreMaximo,
        alturaCm: 1080,
        dibujoCm: 1050,
        margenCm: 1050,
        minCm: 400,
        maxCm: 1050,
        margenRecortado: true,
      );
      expect(sobre, contains('Con 10,80 metros el agua llega más lejos de lo que se ve.'));
      expect(sobre, isNot(contains('pasar los puntos')));
    });
  });

  group('I2: la capa de agua no se puede leer', () {
    for (final (altura, texto) in [(10.50, '10,50'), (10.80, '10,80')]) {
      testWidgets('agua/1050.json roto con $texto m: el dibujo se tapa y la línea va con aviso', (t) async {
        final s = t.ensureSemantics();
        await mostrarMapa(
          t,
          datosCon(altura, nivel: 'evacuacion'),
          fuente: fuenteReal(archivos: {'agua/1050.json': capaRota}),
        );
        expect(lectura(texto), findsOneWidget);
        expect(lineaConAviso(t, textoDibujoIlegible), isTrue);
        // El mapa casi sin agua no queda a la vista como si valiera.
        expect(find.byKey(const ValueKey('mapa-dibujo-ilegible')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('mapa-dibujo-ilegible')),
            matching: find.text(textoDibujoIlegible),
          ),
          findsOneWidget,
        );
        expect(resumenEnPantalla(t), contains('No se pudo leer el dibujo del agua para esta altura.'));
        expect(t.takeException(), isNull);
        s.dispose();
      });
    }

    testWidgets('con la capa legible no hay recuadro sobre el mapa', (t) async {
      await mostrarMapa(t, datosCon(10.50, nivel: 'evacuacion'), fuente: fuenteReal());
      expect(find.byKey(const ValueKey('mapa-dibujo-ilegible')), findsNothing);
      expect(find.text(textoDibujoIlegible), findsNothing);
    });

    testWidgets('si la de arriba sirve se usa esa (sin recuadro), como antes', (t) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteReal(archivos: {'agua/0700.json': capaRota}),
      );
      expect(find.byKey(const ValueKey('mapa-dibujo-ilegible')), findsNothing);
      expect(
        find.text('No se pudo leer el dibujo de 7,00 m. Se muestra el de 7,10 m, con un poco más de agua.'),
        findsOneWidget,
      );
    });
  });

  group('M1: la zona baja (agua/0400.json) no valida', () {
    testWidgets('por debajo del mínimo: no se dibuja otra capa con su estilo, se dice, y el margen sigue', (t) async {
      await mostrarMapa(
        t,
        datosCon(3.50, nivel: 'normal'),
        fuente: fuenteReal(archivos: {'agua/0400.json': capaRota}),
      );
      expect(lectura('3,50'), findsOneWidget);
      expect(find.byType(CapaZonaBaja), findsNothing);
      expect(find.textContaining(textoLeyendaZonaBaja), findsNothing);
      expect(find.text('No se pudo leer el dibujo de la zona baja de la costa.'), findsOneWidget);
      // El margen (de 4,00, reemplazado por 4,10: más agua) se sigue pintando.
      final c = ColoresMapa.actuales();
      expect(
        t
            .widgetList<PolygonLayer>(find.byType(PolygonLayer))
            .expand((l) => l.polygons)
            .where((p) => p.color == c.margen && p.borderColor == c.bordeMargen),
        isNotEmpty,
      );
    });

    testWidgets('en rango: el agua se dibuja y la capa de 4,10 no aparece como zona baja', (t) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteReal(archivos: {'agua/0400.json': capaRota}),
      );
      expect(lectura('7,00'), findsOneWidget);
      expect(find.byType(CapaZonaBaja), findsNothing);
      expect(find.byType(CapaRayado), findsOneWidget);
      expect(find.textContaining(textoLeyendaZonaBaja), findsNothing);
    });

    testWidgets('con la zona baja legible se dibuja con su estilo (control)', (t) async {
      await mostrarMapa(t, datosCon(3.50, nivel: 'normal'), fuente: fuenteReal());
      expect(find.byType(CapaZonaBaja), findsOneWidget);
    });
  });

  group('M2/M3: índice con versión, mínimo o margen raros', () {
    Map<String, dynamic> base() => indiceDePrueba();

    test('rechaza version distinta de 1', () {
      expect(() => IndiceMapa.desdeJson(base()..['version'] = 2), rechazaPor('version'));
      expect(() => IndiceMapa.desdeJson(base()..['version'] = 0), rechazaPor('version'));
      expect(() => IndiceMapa.desdeJson(base()..['version'] = '1'), rechazaPor('version'));
      expect(IndiceMapa.desdeJson(base()).version, 1);
    });

    test('rechaza min_m que no es múltiplo de paso_m', () {
      final j = base()
        ..['min_m'] = 4.05
        ..['max_m'] = 4.35;
      expect(() => IndiceMapa.desdeJson(j), rechazaPor('múltiplo'));
    });

    test('rechaza margen_m menor que 0,10 m', () {
      Map<String, dynamic> conMargen(double m) => base()..['modelo'] = {...base()['modelo'] as Map, 'margen_m': m};
      expect(() => IndiceMapa.desdeJson(conMargen(0)), rechazaPor('margen'));
      expect(() => IndiceMapa.desdeJson(conMargen(0.05)), rechazaPor('margen'));
      expect(() => IndiceMapa.desdeJson(conMargen(0.09)), rechazaPor('margen'));
      expect(IndiceMapa.desdeJson(conMargen(0.1)).margenCm, 10);
      expect(IndiceMapa.desdeJson(conMargen(0.5)).margenCm, 50);
    });

    test('el repositorio deja el mapa no disponible (con el motivo)', () async {
      final r = RepositorioMapa(fuenteDePrueba(indice: (j) => j['version'] = 2));
      final e = await r.indice();
      expect(e, isA<IndiceNoDisponible>());
      expect((e as IndiceNoDisponible).motivo, contains('version'));
    });
  });

  group('M9: aCm redondea hacia arriba', () {
    test('sin errores de coma flotante en los centímetros exactos', () {
      for (var i = 0; i <= 2000; i++) {
        expect(aCm(i / 100), i, reason: '${i / 100}');
        expect(aCm(i * 0.01), i, reason: '$i × 0,01');
      }
      expect(aCm(6.7), 670);
      expect(aCm(0.1), 10);
      expect(aCm(10.5), 1050);
    });

    test('lo que pasa de un centímetro sube, nunca baja', () {
      expect(aCm(5.704), 571);
      expect(aCm(5.7001), 571);
      expect(aCm(5.695), 570);
      expect(redondearArriba(5.704), 580); // antes 5,704 → 570: menos agua que la real
      expect(redondearArriba(5.70), 570);
      expect(redondearArriba(5.63), 570);
    });
  });

  group('M8: licencias de los datos', () {
    test('assets/mapa/LICENSE-DATOS.md existe, declara ODbL, IDE y Dinagua, y no está en el índice', () {
      final licencia = File('assets/mapa/LICENSE-DATOS.md');
      expect(licencia.existsSync(), isTrue);
      final texto = licencia.readAsStringSync();
      expect(texto, contains('Open Database License (ODbL) 1.0'));
      expect(texto, contains('© colaboradores de OpenStreetMap'));
      expect(texto, contains('MDT urbano de Paysandú, 1 m'));
      expect(texto, contains('MDT nacional, 2,5 m'));
      expect(texto, contains('Licencia de Datos Abiertos – Uruguay'));
      expect(texto, contains('Dinagua no publicó una licencia'));
      expect(texto, contains('Modificaciones'));
      // No es un archivo del contrato: el índice (y su sha256) no lo nombra.
      expect(File('assets/mapa/indice.json').readAsStringSync(), isNot(contains('LICENSE')));
      // Entra en el APK porque pubspec.yaml declara la carpeta entera.
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/mapa/\n'));
    });

    test('hoja Fuentes: ODbL de la base derivada, productos MDT y Dinagua sin licencia publicada', () {
      final fuentes = {for (final (titulo, texto) in textosFuentes) titulo: texto};
      expect(fuentes['Calles, río y barrios'], contains('ODbL 1.0'));
      expect(fuentes['Calles, río y barrios'], contains('se comparten con la misma licencia'));
      final terreno = fuentes['Terreno']!;
      expect(terreno, contains('terreno urbano de Paysandú, 1 m (vuelo de 2017)'));
      expect(terreno, contains('nacional, 2,5 m'));
      expect(terreno, contains('Ortoimagen y modelo digital del terreno de cobertura nacional'));
      expect(terreno, contains('Licencia de Datos Abiertos – Uruguay'));
      expect(terreno, contains('Datos modificados'));
      expect(fuentes['Crecidas medidas'], contains('Dinagua no publicó una licencia'));
      expect(fuentes['Altura del río y pronóstico'], contains('Comisión Administradora del Río Uruguay'));
    });
  });

  group('leyenda: fila de la línea de hoy', () {
    test('textos de la fila', () {
      expect(textoLeyendaHoy, 'Hasta dónde llega el agua con el río de hoy');
      expect(textoLeyendaUltimoDato, 'Hasta dónde llega el agua con el último dato');
    });

    testWidgets('al simular otra altura aparece con el texto de la constante', (t) async {
      await mostrarMapa(t, datosCon(6.95, nivel: 'evacuacion'), fuente: fuenteReal());
      expect(find.text('$textoLeyendaHoy (línea gruesa)'), findsNothing); // mirando hoy no hay línea
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(lectura('7,10'), findsOneWidget);
      expect(find.text('$textoLeyendaHoy (línea gruesa)'), findsOneWidget);
    });

    testWidgets('sin conexión dice "el último dato"', (t) async {
      await mostrarMapa(t, datosCon(6.95, nivel: 'evacuacion', sinConexion: true), fuente: fuenteReal());
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(find.text('$textoLeyendaUltimoDato (línea gruesa)'), findsOneWidget);
    });
  });
}

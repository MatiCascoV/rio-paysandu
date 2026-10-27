import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rio_paysandu/crecidas/estilo_crecidas.dart';
import 'package:rio_paysandu/crecidas/modelos_crecidas.dart';
import 'package:rio_paysandu/crecidas/repositorio_crecidas.dart';
import 'package:rio_paysandu/pantallas/crecidas.dart';
import 'package:rio_paysandu/tema.dart';

/// Los archivos reales de assets/crecidas/, en memoria.
Map<String, Uint8List> archivosReales() {
  final carpeta = Directory('assets/crecidas');
  return {
    for (final f in carpeta.listSync(recursive: true).whereType<File>())
      f.path.substring(carpeta.path.length + 1).replaceAll(r'\', '/'): f.readAsBytesSync(),
  };
}

Map<String, dynamic> indiceReal() =>
    jsonDecode(File('assets/crecidas/indice.json').readAsStringSync()) as Map<String, dynamic>;

Uint8List bytesDe(Object j) => Uint8List.fromList(utf8.encode(jsonEncode(j)));

Future<void> mostrar(
  WidgetTester t,
  RepositorioCrecidas repo, {
  Size tamano = const Size(393, 852),
  bool oscuro = false,
}) async {
  t.view.physicalSize = tamano * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  Colores.oscuro = oscuro;
  addTearDown(() => Colores.oscuro = false);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: temaApp(),
      home: Scaffold(body: PantallaCrecidas(repositorio: repo)),
    ),
  );
  await t.pumpAndSettle();
}

String etiquetaDelMapa(WidgetTester t) {
  final nodo = t.getSemantics(find.byKey(const ValueKey('crecidas-mapa')).first);
  // La etiqueta está en el contenedor de arriba del mapa.
  SemanticsNode? n = nodo;
  while (n != null && !n.label.contains('Dinagua')) {
    n = n.parent;
  }
  return n?.label ?? '';
}

/// Anuncios que la app le manda al lector de pantalla.
List<String> escucharAnuncios(WidgetTester t) {
  final anuncios = <String>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
    if (m is Map && m['type'] == 'announce') anuncios.add((m['data'] as Map)['message'] as String);
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
  );
  return anuncios;
}

Future<void> elegir(WidgetTester t, String texto) async {
  final opcion = find.text(texto);
  await t.scrollUntilVisible(opcion, 200, scrollable: find.byType(Scrollable).last);
  await t.tap(opcion);
  await t.pumpAndSettle();
}

/// Punto en polígono (rayo hacia el este).
bool adentro(LatLng q, List<LatLng> anillo) {
  var dentro = false;
  for (var i = 0, j = anillo.length - 1; i < anillo.length; j = i++) {
    final a = anillo[i], b = anillo[j];
    if ((a.latitude > q.latitude) != (b.latitude > q.latitude) &&
        q.longitude <
            (b.longitude - a.longitude) * (q.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
      dentro = !dentro;
    }
  }
  return dentro;
}

/// Área en grados² (alcanza para comparar polígonos).
double area(List<LatLng> anillo) {
  var s = 0.0;
  for (var i = 0, j = anillo.length - 1; i < anillo.length; j = i++) {
    s += anillo[j].longitude * anillo[i].latitude - anillo[i].longitude * anillo[j].latitude;
  }
  return s.abs() / 2;
}

/// El índice real con un campo de la primera crecida cambiado.
Map<String, dynamic> indiceCon(void Function(Map entrada) cambiar) {
  final ind = indiceReal();
  cambiar((ind['crecidas'] as List).first as Map);
  return ind;
}

void main() {
  group('datos', () {
    test('el índice real es válido: 5 crecidas de Dinagua, la más reciente primero', () async {
      final repo = RepositorioCrecidas(FuenteMemoria(archivosReales()));
      final e = await repo.indice();
      expect(e, isA<IndiceListo>());
      final ind = (e as IndiceListo).indice;
      expect(ind.crecidas.map((c) => c.clave), [
        'curvas/2025-07.json',
        'curvas/2019-01.json',
        'curvas/2017-06.json',
        'curvas/2015-12.json',
        'curvas/2009-11.json',
      ]);
      expect(ind.crecidas.map((c) => c.alturaM), [6.58, 8.45, 8.35, 9.12, 8.93]);
      expect(ind.crecidas.every((c) => c.fuente == 'Dinagua'), isTrue);
      expect(ind.crecidas.first.fecha, DateTime(2025, 7, 3));
    });

    test('el fondo y los 5 bordes se leen, con huella y tamaño correctos, y son líneas', () async {
      final fuente = FuenteMemoria(archivosReales());
      final repo = RepositorioCrecidas(fuente);
      final ind = ((await repo.indice()) as IndiceListo).indice;
      final base = await repo.base();
      expect(base, isNotNull);
      expect(base!.agua, isNotEmpty);
      expect(base.calles, isNotEmpty);
      for (final c in ind.crecidas) {
        final b = await repo.borde(c);
        expect(b, isNotNull, reason: c.clave);
        expect(b!.lineas, isNotEmpty);
        // Una segunda vez no se vuelve a leer.
        await repo.borde(c);
        expect(fuente.lecturas[c.clave], 1);
      }
    });

    test('la carpeta solo trae el fondo y las crecidas: nada del modelo de agua', () {
      final nombres = archivosReales().keys.toSet();
      expect(nombres, {
        'indice.json',
        'base.json',
        'LICENSE-DATOS.md',
        'curvas/2009-11.json',
        'curvas/2015-12.json',
        'curvas/2017-06.json',
        'curvas/2019-01.json',
        'curvas/2025-07.json',
      });
      for (final c in (indiceReal()['crecidas'] as List).cast<Map>()) {
        final bytes = File('assets/crecidas/${c['archivo']}').readAsBytesSync();
        expect(bytes.length, c['bytes']);
        expect(crypto.sha256.convert(bytes).toString(), c['sha256']);
      }
    });

    test('ningún borde cruza el río: no queda ningún tramo de más de 250 m con 10 % o más en el río', () async {
      final repo = RepositorioCrecidas(FuenteMemoria(archivosReales()));
      final ind = ((await repo.indice()) as IndiceListo).indice;
      final base = (await repo.base())!;
      // El río Uruguay es el polígono de agua más grande del fondo.
      final rio = base.agua.reduce((a, b) => area(a.exterior) >= area(b.exterior) ? a : b);
      bool enRio(LatLng p) => adentro(p, rio.exterior) && !rio.huecos.any((h) => adentro(p, h));
      const d = Distance();
      var revisados = 0;
      for (final c in ind.crecidas) {
        final b = (await repo.borde(c))!;
        for (final l in b.lineas) {
          for (var i = 1; i < l.puntos.length; i++) {
            final a = l.puntos[i - 1], z = l.puntos[i];
            final m = d.as(LengthUnit.Meter, a, z);
            if (m <= 250) continue;
            revisados++;
            // Muestras cada ~5 m a lo largo del tramo.
            final n = (m / 5).ceil();
            var dentro = 0;
            for (var k = 0; k <= n; k++) {
              final f = k / n;
              if (enRio(
                LatLng(a.latitude + (z.latitude - a.latitude) * f, a.longitude + (z.longitude - a.longitude) * f),
              )) {
                dentro++;
              }
            }
            expect(dentro / (n + 1), lessThan(0.10), reason: '${c.clave}: tramo de ${m.round()} m en $a -> $z');
          }
        }
      }
      // Quedan tramos largos, pero en tierra (300 a 370 m en 2009 y 2019).
      expect(revisados, greaterThan(0));
    });

    test('control de los bordes: cantidad de puntos y largo de cada crecida', () async {
      final repo = RepositorioCrecidas(FuenteMemoria(archivosReales()));
      final ind = ((await repo.indice()) as IndiceListo).indice;
      const d = Distance();
      // Salida de docs/crecidas/bordes_crecidas.py: puntos por línea y km de
      // borde (2025 trae, además, un anillito cerrado de 14 m).
      const esperado = {
        'curvas/2025-07.json': ([2559, 4], 36.3),
        'curvas/2019-01.json': ([1157], 27.1),
        'curvas/2017-06.json': ([583], 16.9),
        'curvas/2015-12.json': ([452], 19.8),
        'curvas/2009-11.json': ([266], 17.4),
      };
      expect(ind.crecidas.map((c) => c.clave).toSet(), esperado.keys.toSet());
      for (final c in ind.crecidas) {
        final b = (await repo.borde(c))!;
        final (puntos, km) = esperado[c.clave]!;
        expect(b.lineas.map((l) => l.puntos.length).toList(), puntos, reason: c.clave);
        var metros = 0.0;
        for (final l in b.lineas) {
          for (var i = 1; i < l.puntos.length; i++) {
            metros += d.as(LengthUnit.Meter, l.puntos[i - 1], l.puntos[i]);
          }
        }
        expect(metros / 1000, closeTo(km, 0.2), reason: c.clave);
      }
    });

    test('un borde con huella cambiada no se usa', () async {
      final archivos = archivosReales();
      final ind = indiceReal();
      ((ind['crecidas'] as List).first as Map)['sha256'] = '0' * 64;
      archivos['indice.json'] = bytesDe(ind);
      final repo = RepositorioCrecidas(FuenteMemoria(archivos));
      final i = ((await repo.indice()) as IndiceListo).indice;
      expect(await repo.borde(i.crecidas.first), isNull);
      expect(await repo.borde(i.crecidas[1]), isNotNull);
    });

    test('una crecida sin fuente, sin fecha o fuera de rango se saltea; si no queda ninguna, no hay datos', () {
      final ind = indiceReal();
      final lista = ind['crecidas'] as List;
      (lista[0] as Map).remove('fuente');
      (lista[1] as Map)['fecha'] = 'enero';
      (lista[2] as Map)['altura_m'] = 45;
      (lista[3] as Map)['archivo'] = '../secreto.json';
      final i = IndiceCrecidas.desdeJson(ind);
      expect(i.crecidas.map((c) => c.clave), ['curvas/2009-11.json']);
      (lista[4] as Map)['bytes'] = -1;
      expect(() => IndiceCrecidas.desdeJson(ind), throwsA(isA<ErrorCrecidas>()));
    });

    test('una fecha imposible o una fuente que no es Dinagua: la crecida se saltea', () {
      for (final fecha in ['2019-02-30', '2019-13-01', '2019-00-10', '2019-1-23']) {
        final i = IndiceCrecidas.desdeJson(indiceCon((e) => e['fecha'] = fecha));
        expect(i.crecidas, hasLength(4), reason: fecha);
      }
      for (final fuente in ['CARU', 'dinagua', '']) {
        final i = IndiceCrecidas.desdeJson(indiceCon((e) => e['fuente'] = fuente));
        expect(i.crecidas, hasLength(4), reason: fuente);
      }
      // Bisiesto: el 29 de febrero de 2024 existe.
      final i = IndiceCrecidas.desdeJson(indiceCon((e) => e['fecha'] = '2024-02-29'));
      expect(i.crecidas.map((c) => c.fecha), contains(DateTime(2024, 2, 29)));
    });

    test('un archivo que no pesa lo que dice el índice no se usa (aunque la huella sea la suya)', () async {
      final archivos = archivosReales();
      final ind = indiceReal();
      final entrada = (ind['crecidas'] as List).cast<Map>().firstWhere((c) => c['archivo'] == 'curvas/2017-06.json');
      entrada['bytes'] = (entrada['bytes'] as int) + 1;
      archivos['indice.json'] = bytesDe(ind);
      final repo = RepositorioCrecidas(FuenteMemoria(archivos));
      final i = ((await repo.indice()) as IndiceListo).indice;
      expect(await repo.borde(i.crecidas.firstWhere((c) => c.clave == 'curvas/2017-06.json')), isNull);
      expect(await repo.borde(i.crecidas.firstWhere((c) => c.clave == 'curvas/2019-01.json')), isNotNull);
      // Lo mismo con el fondo.
      ind['base']['bytes'] = (ind['base']['bytes'] as int) - 1;
      archivos['indice.json'] = bytesDe(ind);
      expect(await RepositorioCrecidas(FuenteMemoria(archivos)).base(), isNull);
    });

    test('el aviso de la app es el mismo que el de LICENSE-DATOS.md', () {
      String junto(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
      final licencia = junto(File('assets/crecidas/LICENSE-DATOS.md').readAsStringSync());
      expect(licencia, contains(textoFuentesDeslinde));
      // Y el script de la base derivada (ODbL §4.6) está en este repositorio.
      expect(licencia, contains('docs/crecidas/extraer_osm.py'));
      expect(File('../docs/crecidas/extraer_osm.py').existsSync(), isTrue);
    });

    test('índice ausente, roto o de otra versión: no disponible', () async {
      expect(await RepositorioCrecidas(FuenteMemoria({})).indice(), isA<IndiceNoDisponible>());
      expect(
        await RepositorioCrecidas(FuenteMemoria({'indice.json': Uint8List.fromList(utf8.encode('{no'))})).indice(),
        isA<IndiceNoDisponible>(),
      );
      final otra = indiceReal()..['version'] = 2;
      expect(
        await RepositorioCrecidas(FuenteMemoria({'indice.json': bytesDe(otra)})).indice(),
        isA<IndiceNoDisponible>(),
      );
    });

    test('un borde con otra altura que la del índice no se acepta', () async {
      final archivos = archivosReales();
      final borde = jsonDecode(utf8.decode(archivos['curvas/2019-01.json']!)) as Map<String, dynamic>;
      ((borde['features'] as List).first as Map)['properties']['altura_m'] = 7.0;
      final ind = indiceReal();
      final bytes = bytesDe(borde);
      final entrada = (ind['crecidas'] as List).cast<Map>().firstWhere((c) => c['archivo'] == 'curvas/2019-01.json');
      entrada['bytes'] = bytes.length;
      entrada['sha256'] = crypto.sha256.convert(bytes).toString();
      archivos['curvas/2019-01.json'] = bytes;
      archivos['indice.json'] = bytesDe(ind);
      final repo = RepositorioCrecidas(FuenteMemoria(archivos));
      final i = ((await repo.indice()) as IndiceListo).indice;
      expect(await repo.borde(i.crecidas.firstWhere((c) => c.clave == 'curvas/2019-01.json')), isNull);
    });
  });

  group('pantalla', () {
    testWidgets('abre en la crecida más reciente, con altura según Dinagua y fecha', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      expect(find.text('Crecida de julio de 2025'), findsWidgets);
      expect(find.text('6,58 m según Dinagua · 3 de julio de 2025'), findsWidgets);
      final s = t.ensureSemantics();
      expect(
        etiquetaDelMapa(t),
        startsWith('Crecida de julio de 2025, 6,58 metros según Dinagua, del 3 de julio de 2025'),
      );
      s.dispose();
    });

    testWidgets('el aviso aprobado y la escala van arriba del mapa; la fuente, debajo', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final aviso = find.byKey(const ValueKey('aviso-crecidas'));
      expect(aviso, findsOneWidget);
      expect(t.widget<Text>(aviso).data, textoAvisoCrecidas);
      expect(
        textoAvisoCrecidas,
        'Muestra hasta dónde llegó el agua en crecidas anteriores, según Dinagua. La ciudad cambió desde entonces, '
        'así que una crecida igual no llega necesariamente al mismo lugar. No es un pronóstico ni reemplaza las '
        'indicaciones del Cecoed.',
      );
      final escala = find.byKey(const ValueKey('escala-crecidas'));
      expect(
        t.widget<Text>(escala).data,
        'Las alturas de Dinagua pueden no coincidir exactamente con la escala de CARU.',
      );
      final mapa = find.byKey(const ValueKey('crecidas-mapa'));
      final fuente = find.textContaining('Fuente: Dirección Nacional de Aguas (Dinagua)');
      // Lectura, aviso, escala, mapa y fuente, en ese orden.
      expect(
        t.getTopLeft(find.text('6,58 m según Dinagua · 3 de julio de 2025').first).dy,
        lessThan(t.getTopLeft(aviso).dy),
      );
      expect(t.getBottomLeft(aviso).dy, lessThan(t.getTopLeft(escala).dy));
      expect(t.getBottomLeft(escala).dy, lessThan(t.getTopLeft(mapa).dy));
      expect(t.getTopLeft(fuente).dy, greaterThan(t.getBottomLeft(mapa).dy));
      expect(find.text('© OpenStreetMap · Dinagua'), findsOneWidget);
    });

    testWidgets('al elegir otra crecida se anuncia, y cambian la lectura y el resumen para TalkBack', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final s = t.ensureSemantics();
      final anuncios = escucharAnuncios(t);
      await elegir(t, 'Crecida de enero de 2019');
      expect(anuncios, ['Mapa: crecida de enero de 2019, 8,45 metros según Dinagua, del 23 de enero de 2019.']);
      expect(find.text('8,45 m según Dinagua · 23 de enero de 2019'), findsWidgets);
      final resumen = etiquetaDelMapa(t);
      expect(resumen, startsWith('Crecida de enero de 2019, 8,45 metros según Dinagua, del 23 de enero de 2019'));
      expect(resumen, contains('Donde no hay línea no quiere decir que el agua no haya llegado'));
      expect(resumen, contains('Este resumen no dice qué calles o barrios alcanzó el agua.'));
      expect(resumen, contains(textoEscalaCrecidas));
      // La lectura de arriba ya no es región en vivo (no se anuncia dos veces).
      final lectura = t.getSemantics(find.text('Crecida de enero de 2019').first);
      expect(lectura.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
      s.dispose();
    });

    testWidgets('las opciones son botones de radio que TalkBack lee con "metros" y sin "·"', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final s = t.ensureSemantics();
      await elegir(t, 'Crecida de enero de 2019');
      final elegida = t.getSemantics(find.text('Crecida de enero de 2019').last);
      expect(
        elegida,
        isSemantics(
          label: 'Crecida de enero de 2019. 8,45 metros según Dinagua, 23 de enero de 2019',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          isButton: false,
          hasTapAction: true,
        ),
      );
      expect(
        t.getSemantics(find.text('Crecida de julio de 2025').last),
        isSemantics(hasCheckedState: true, isChecked: false, isInMutuallyExclusiveGroup: true, hasTapAction: true),
      );
      // La lectura de arriba tampoco dice "m" ni "·".
      final detalle = t.getSemantics(find.text('8,45 m según Dinagua · 23 de enero de 2019').first);
      expect(detalle.label, 'Crecida de enero de 2019\n8,45 metros según Dinagua, 23 de enero de 2019');
      // La atribución sobre el mapa no se lee (está en la fuente, abajo).
      expect(find.bySemanticsLabel(RegExp('© OpenStreetMap · Dinagua')), findsNothing);
      s.dispose();
    });

    testWidgets('"Ver todas": solo las que tienen borde, cada una con su trazo nombrado, y acerca a la costa', (
      t,
    ) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final s = t.ensureSemantics();
      final anuncios = escucharAnuncios(t);
      final control = t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
      expect(control.camera.zoom, lessThan(zoomParaDistinguir));
      await elegir(t, 'Ver todas');
      expect(anuncios, ['Mapa: las 5 crecidas medidas por Dinagua, juntas.']);
      expect(find.text('Todas las crecidas'), findsOneWidget);
      // Acercó a la costa céntrica, donde las líneas se separan.
      expect(control.camera.zoom, closeTo(zoomVerTodas, 0.01));
      expect(find.text(textoAcercarParaDistinguir), findsNothing);
      final resumen = etiquetaDelMapa(t);
      expect(resumen, startsWith('Las 5 crecidas medidas por Dinagua'));
      expect(
        resumen,
        contains('diciembre de 2015, 9,12 metros según Dinagua, del 10 de diciembre de 2015, raya y punto'),
      );
      expect(
        resumen,
        contains('noviembre de 2009, 8,93 metros según Dinagua, del 10 de noviembre de 2009, raya y dos puntos'),
      );
      expect(
        find.text('Raya y punto: crecida de diciembre de 2015 (9,12 m según Dinagua, 10 de diciembre de 2015).'),
        findsOneWidget,
      );
      expect(
        find.text('Línea continua: crecida de julio de 2025 (6,58 m según Dinagua, 3 de julio de 2025).'),
        findsOneWidget,
      );
      expect(find.text('En el mapa: trazos.'), findsOneWidget);
      final capa = t.widgetList<PolylineLayer>(find.byType(PolylineLayer)).last;
      expect(capa.polylines.map((p) => p.color).toSet(), hasLength(5));
      // Al alejar con "−" aparece la pista para acercar.
      await t.scrollUntilVisible(find.byTooltip('Alejar'), -200, scrollable: find.byType(Scrollable).last);
      await t.tap(find.byTooltip('Alejar'));
      await t.pumpAndSettle();
      expect(find.text(textoAcercarParaDistinguir), findsOneWidget);
      s.dispose();
    });

    test('los cinco trazos son distintos entre sí, y el de 2009 no se parece al de 2019', () {
      final patrones = [for (var i = 0; i < 5; i++) TrazosMapa.segmentos(i)?.join(',')];
      expect(patrones.toSet(), hasLength(5));
      expect(TrazosMapa.segmentos(4), [16.0, 4.0, 3.0, 4.0, 3.0, 4.0]);
      expect({for (var i = 0; i < 5; i++) TrazosMapa.nombre(i)}, hasLength(5));
      // La muestra repite el dibujo al menos una vez entero.
      for (var i = 1; i < 5; i++) {
        final largo = TrazosMapa.segmentos(i)!.fold<double>(0, (a, b) => a + b);
        expect(anchoMuestra - 8, greaterThan(largo * 1.5), reason: '$i');
      }
      expect(anchoMuestra, inInclusiveRange(56, 64));
    });

    testWidgets('el mapa se maneja con los dedos; fuera del mapa, el dedo desplaza la página', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final mapa = t.widget<FlutterMap>(find.byType(FlutterMap));
      final flags = mapa.options.interactionOptions.flags;
      expect(flags & InteractiveFlag.drag, isNot(0));
      expect(flags & InteractiveFlag.pinchZoom, isNot(0));
      expect(flags & InteractiveFlag.doubleTapZoom, isNot(0));
      expect(flags & InteractiveFlag.rotate, 0);
      // El mapa ocupa menos de la mitad de la pantalla: siempre queda dónde apoyar el dedo para desplazar.
      expect(t.getSize(find.byType(FlutterMap)).height, lessThan(852 / 2));
      final control = mapa.mapController!;
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).last).position;
      // Arrastrar fuera del mapa (sobre el título) desplaza la página y no mueve el mapa.
      final inicial = control.camera.center;
      await t.dragFrom(t.getCenter(find.text('Crecidas anteriores')), const Offset(0, -150));
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(100));
      expect(control.camera.center, inicial);
      // Con el mapa a la vista, arrastrar sobre él mueve el mapa, no la página.
      await t.ensureVisible(find.byType(FlutterMap));
      await t.pumpAndSettle();
      final pagina = scroll.pixels;
      final antes = control.camera.center;
      await t.dragFrom(t.getCenter(find.byType(FlutterMap)), const Offset(-120, -150));
      await t.pumpAndSettle();
      expect(scroll.pixels, pagina);
      expect(control.camera.center.latitude, lessThan(antes.latitude));
      expect(control.camera.center.longitude, greaterThan(antes.longitude));
      // Y debajo del mapa (sobre la fuente) el dedo vuelve a desplazar la página.
      final quieto = control.camera.center;
      await t.dragFrom(t.getCenter(find.textContaining('Fuente: Dirección Nacional')), const Offset(0, -200));
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(pagina + 100));
      expect(control.camera.center, quieto);
    });

    testWidgets('las flechas y + / − mueven el mapa sin arrastrar; los botones tienen borde', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final control = t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
      final zoom = control.camera.zoom;
      await t.tap(find.byTooltip('Acercar'));
      await t.pump();
      expect(control.camera.zoom, zoom + 1);
      final centro = control.camera.center;
      await t.scrollUntilVisible(find.byTooltip('Ver más al norte'), 100, scrollable: find.byType(Scrollable).last);
      await t.tap(find.byTooltip('Ver más al norte'));
      await t.pump();
      expect(control.camera.center.latitude, greaterThan(centro.latitude));
      await t.scrollUntilVisible(find.byTooltip('Ver toda la zona'), -100, scrollable: find.byType(Scrollable).last);
      await t.tap(find.byTooltip('Ver toda la zona'));
      await t.pump();
      expect(control.camera.zoom, closeTo(zoom, 0.01));
      final boton = t.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.add), matching: find.byType(IconButton)));
      expect(boton.style!.side!.resolve({})!.color, Colores.bordeControl);
    });

    testWidgets('pantalla completa: misma crecida, cerrar, Atrás, y vuelve con el mismo encuadre', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final s = t.ensureSemantics();
      final control = t.widget<FlutterMap>(find.byKey(const ValueKey('crecidas-mapa'))).mapController!;
      final boton = find.byKey(const ValueKey('pantalla-completa'));
      expect(t.getSize(boton).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Pantalla completa'), findsOneWidget);
      await t.scrollUntilVisible(boton, 100, scrollable: find.byType(Scrollable).last);
      await t.tap(boton);
      await t.pumpAndSettle();
      final completo = find.byKey(const ValueKey('crecidas-mapa-completo'));
      expect(completo, findsOneWidget);
      // Ocupa todo el teléfono.
      expect(t.getSize(completo), const Size(393, 852));
      expect(find.text('Crecida de julio de 2025\n6,58 m según Dinagua · 3 de julio de 2025'), findsOneWidget);
      expect(find.text('No es un pronóstico.'), findsOneWidget);
      expect(find.text('© OpenStreetMap · Dinagua'), findsWidgets);
      final cerrar = find.byKey(const ValueKey('cerrar-pantalla-completa'));
      expect(t.getSize(cerrar).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Cerrar'), findsOneWidget);
      final mapa = t.widget<FlutterMap>(completo);
      expect(mapa.options.interactionOptions.flags & InteractiveFlag.drag, isNot(0));
      expect(mapa.options.interactionOptions.flags & InteractiveFlag.rotate, 0);
      // Misma crecida: el mismo borde.
      final bordes = t.widgetList<PolylineLayer>(find.descendant(of: completo, matching: find.byType(PolylineLayer)));
      expect(bordes.last.key, const ValueKey('bordes-curvas/2025-07.json-false'));
      // + y arrastre en pantalla completa; Atrás de Android cierra.
      await t.tap(find.descendant(of: find.byType(PantallaCompletaCrecidas), matching: find.byTooltip('Acercar')));
      await t.pumpAndSettle();
      await t.dragFrom(t.getCenter(completo), const Offset(80, 0));
      await t.pumpAndSettle();
      final camara = mapa.mapController!.camera;
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(completo, findsNothing);
      expect(control.camera.zoom, closeTo(camara.zoom, 0.001));
      expect(control.camera.center.longitude, closeTo(camara.center.longitude, 1e-6));
      // Y el botón Cerrar también cierra.
      await t.tap(boton);
      await t.pumpAndSettle();
      await t.tap(cerrar);
      await t.pumpAndSettle();
      expect(completo, findsNothing);
      s.dispose();
    });

    testWidgets('"Ver todas" también se abre en pantalla completa', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      await elegir(t, 'Ver todas');
      final boton = find.byKey(const ValueKey('pantalla-completa'));
      await t.scrollUntilVisible(boton, -100, scrollable: find.byType(Scrollable).last);
      await t.tap(boton);
      await t.pumpAndSettle();
      expect(find.text('Todas las crecidas (5)'), findsOneWidget);
      final completo = find.byKey(const ValueKey('crecidas-mapa-completo'));
      final capa = t
          .widgetList<PolylineLayer>(find.descendant(of: completo, matching: find.byType(PolylineLayer)))
          .last;
      expect(capa.polylines.map((p) => p.color).toSet(), hasLength(5));
      expect(t.widget<FlutterMap>(completo).mapController!.camera.zoom, closeTo(zoomVerTodas, 0.01));
    });

    testWidgets('un redibujo de la página no rearma el mapa ni vuelve a proyectar las calles', (t) async {
      final repo = RepositorioCrecidas(FuenteMemoria(archivosReales()));
      t.view.physicalSize = const Size(393, 852) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      late StateSetter redibujar;
      var vueltas = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: temaApp(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                redibujar = setState;
                vueltas++;
                return PantallaCrecidas(repositorio: repo);
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final mapa = t.widget(find.byType(FlutterMap));
      final calles = t.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();
      redibujar(() {}); // como el reloj de 5 minutos de main.dart
      await t.pump();
      expect(vueltas, 2);
      expect(identical(t.widget(find.byType(FlutterMap)), mapa), isTrue);
      final despues = t.widgetList<PolylineLayer>(find.byType(PolylineLayer)).toList();
      for (var i = 0; i < calles.length; i++) {
        expect(identical(despues[i], calles[i]), isTrue);
      }
    });

    testWidgets('nada del nivel de hoy ni del modelo de agua', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      for (final palabra in [
        'Simulación',
        'simulación',
        'hoy',
        'Hoy',
        'margen',
        'sin validar',
        'aislada',
        'llegaría',
      ]) {
        expect(find.textContaining(palabra), findsNothing, reason: palabra);
      }
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(PolygonLayer), findsOneWidget); // solo el cauce del río
    });

    testWidgets('sin datos lo dice con palabras', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria({})));
      expect(find.text(textoCrecidasNoDisponibles), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('si un borde no se puede leer, lo avisa, también en "Ver todas", y las demás siguen', (t) async {
      final archivos = archivosReales()..remove('curvas/2025-07.json');
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivos)));
      final s = t.ensureSemantics();
      expect(find.text('No se pudo leer el borde de esta crecida.'), findsOneWidget);
      expect(
        etiquetaDelMapa(t),
        startsWith(
          'Crecida de julio de 2025, 6,58 metros según Dinagua, del 3 de julio de 2025: '
          'no se pudo leer el borde',
        ),
      );
      await elegir(t, 'Crecida de junio de 2017');
      expect(find.text('No se pudo leer el borde de esta crecida.'), findsNothing);
      await elegir(t, 'Ver todas');
      expect(find.text('Las 4 crecidas medidas por Dinagua, juntas.'), findsOneWidget);
      expect(
        find.text('No se pudo leer el borde de la crecida de julio de 2025: no aparece en el mapa.'),
        findsOneWidget,
      );
      final resumen = etiquetaDelMapa(t);
      expect(resumen, startsWith('Las 4 crecidas medidas por Dinagua'));
      expect(resumen, contains('No se pudo leer el borde de la crecida de julio de 2025.'));
      expect(resumen, isNot(contains('julio de 2025, 6,58')));
      expect(find.textContaining('crecida de julio de 2025 (6,58'), findsNothing); // fuera de la leyenda
      s.dispose();
    });

    for (final oscuro in [false, true]) {
      testWidgets('320 dp con letra al 200 %: nada se desborda (${oscuro ? 'oscuro' : 'claro'})', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await mostrar(
          t,
          RepositorioCrecidas(FuenteMemoria(archivosReales())),
          tamano: const Size(320, 640),
          oscuro: oscuro,
        );
        expect(t.takeException(), isNull);
        await elegir(t, 'Ver todas');
        expect(t.takeException(), isNull);
        final boton = find.byKey(const ValueKey('pantalla-completa'));
        await t.scrollUntilVisible(boton, -200, scrollable: find.byType(Scrollable).last);
        await t.tap(boton);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('No es un pronóstico.'), findsOneWidget);
      });
    }
  });
}

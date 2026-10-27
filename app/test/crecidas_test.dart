import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

Map<String, dynamic> indiceReal() => jsonDecode(File('assets/crecidas/indice.json').readAsStringSync()) as Map<String, dynamic>;

Uint8List bytesDe(Object j) => Uint8List.fromList(utf8.encode(jsonEncode(j)));

Future<void> mostrar(WidgetTester t, RepositorioCrecidas repo, {Size tamano = const Size(393, 852), bool oscuro = false}) async {
  t.view.physicalSize = tamano * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  Colores.oscuro = oscuro;
  addTearDown(() => Colores.oscuro = false);
  await t.pumpWidget(MaterialApp(
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: temaApp(),
    home: Scaffold(body: PantallaCrecidas(repositorio: repo)),
  ));
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

    test('ningún borde cruza el cauce: no quedan los cierres rectos del relevamiento', () async {
      final repo = RepositorioCrecidas(FuenteMemoria(archivosReales()));
      final ind = ((await repo.indice()) as IndiceListo).indice;
      const d = Distance();
      for (final c in ind.crecidas) {
        final b = (await repo.borde(c))!;
        for (final l in b.lineas) {
          for (var i = 1; i < l.puntos.length; i++) {
            final m = d.as(LengthUnit.Meter, l.puntos[i - 1], l.puntos[i]);
            // Los cierres de Dinagua miden entre 400 m y 2,9 km.
            expect(m, lessThan(400), reason: '${c.clave}: tramo de ${m.round()} m');
          }
        }
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

    test('índice ausente, roto o de otra versión: no disponible', () async {
      expect(await RepositorioCrecidas(FuenteMemoria({})).indice(), isA<IndiceNoDisponible>());
      expect(
        await RepositorioCrecidas(FuenteMemoria({'indice.json': Uint8List.fromList(utf8.encode('{no'))})).indice(),
        isA<IndiceNoDisponible>(),
      );
      final otra = indiceReal()..['version'] = 2;
      expect(await RepositorioCrecidas(FuenteMemoria({'indice.json': bytesDe(otra)})).indice(), isA<IndiceNoDisponible>());
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
      expect(etiquetaDelMapa(t), startsWith('Crecida de julio de 2025, 6,58 metros según Dinagua'));
      s.dispose();
    });

    testWidgets('el aviso aprobado y la fuente se ven sin tocar nada, en la primera pantalla', (t) async {
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
      // Arranca dentro de la pantalla del teléfono (852 dp de alto).
      expect(t.getTopLeft(aviso).dy, lessThan(852));
      expect(find.textContaining('Fuente: Dirección Nacional de Aguas (Dinagua)'), findsOneWidget);
      expect(find.text('© OpenStreetMap · Dinagua'), findsOneWidget);
    });

    testWidgets('al elegir otra crecida cambian la lectura y el resumen para TalkBack', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final s = t.ensureSemantics();
      final opcion = find.text('Crecida de enero de 2019');
      await t.scrollUntilVisible(opcion, 200, scrollable: find.byType(Scrollable).last);
      await t.tap(opcion);
      await t.pumpAndSettle();
      expect(find.text('8,45 m según Dinagua · 23 de enero de 2019'), findsWidgets);
      expect(etiquetaDelMapa(t), startsWith('Crecida de enero de 2019, 8,45 metros según Dinagua'));
      expect(etiquetaDelMapa(t), contains('Donde no hay línea no quiere decir que el agua no haya llegado'));
      // La opción elegida se anuncia como elegida.
      expect(
        t.getSemantics(opcion.last),
        isSemantics(isSelected: true, isButton: true, isInMutuallyExclusiveGroup: true),
      );
      expect(
        t.getSemantics(find.text('Crecida de julio de 2025').last),
        isSemantics(isSelected: false, isButton: true),
      );
      s.dispose();
    });

    testWidgets('"Ver todas" muestra las 5 en la leyenda y en el resumen', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final s = t.ensureSemantics();
      final opcion = find.text('Ver todas');
      await t.scrollUntilVisible(opcion, 200, scrollable: find.byType(Scrollable).last);
      await t.tap(opcion);
      await t.pumpAndSettle();
      expect(find.text('Todas las crecidas'), findsOneWidget);
      expect(etiquetaDelMapa(t), startsWith('Las 5 crecidas medidas por Dinagua'));
      expect(find.text('Crecida de diciembre de 2015 (9,12 m según Dinagua).'), findsOneWidget);
      final capa = t.widgetList<PolylineLayer>(find.byType(PolylineLayer)).last;
      expect(capa.polylines.map((p) => p.color).toSet(), hasLength(5));
      s.dispose();
    });

    testWidgets('el mapa no atrapa el desplazamiento: con un dedo se mueve la página', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final mapa = t.widget<FlutterMap>(find.byType(FlutterMap));
      final flags = mapa.options.interactionOptions.flags;
      expect(flags & InteractiveFlag.drag, 0);
      expect(flags & InteractiveFlag.flingAnimation, 0);
      expect(flags & InteractiveFlag.pinchZoom, isNot(0));
      final camara = mapa.mapController!.camera.center;
      final scroll = t.state<ScrollableState>(find.byType(Scrollable).last).position;
      expect(scroll.pixels, 0);
      await t.dragFrom(t.getCenter(find.byType(FlutterMap)), const Offset(0, -250));
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(100));
      expect(mapa.mapController!.camera.center, camara);
      await t.pump(const Duration(seconds: 4)); // se va el aviso de dos dedos
    });

    testWidgets('las flechas y + / − mueven el mapa sin arrastrar', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      final control = t.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
      final zoom = control.camera.zoom;
      await t.tap(find.byTooltip('Acercar'));
      await t.pump();
      expect(control.camera.zoom, zoom + 1);
      final centro = control.camera.center;
      await t.tap(find.byTooltip('Ver más al norte'));
      await t.pump();
      expect(control.camera.center.latitude, greaterThan(centro.latitude));
      await t.tap(find.byTooltip('Ver toda la zona'));
      await t.pump();
      expect(control.camera.zoom, closeTo(zoom, 0.01));
    });

    testWidgets('nada del nivel de hoy ni del modelo de agua', (t) async {
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())));
      for (final palabra in ['Simulación', 'simulación', 'hoy', 'Hoy', 'margen', 'sin validar', 'aislada', 'llegaría']) {
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

    testWidgets('si un borde no se puede leer, lo avisa y las demás siguen', (t) async {
      final archivos = archivosReales()..remove('curvas/2025-07.json');
      await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivos)));
      expect(find.text('No se pudo leer el borde de esta crecida.'), findsOneWidget);
      final opcion = find.text('Crecida de junio de 2017');
      await t.scrollUntilVisible(opcion, 200, scrollable: find.byType(Scrollable).last);
      await t.tap(opcion);
      await t.pumpAndSettle();
      expect(find.text('No se pudo leer el borde de esta crecida.'), findsNothing);
    });

    for (final oscuro in [false, true]) {
      testWidgets('320 dp con letra al 200 %: nada se desborda (${oscuro ? 'oscuro' : 'claro'})', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await mostrar(t, RepositorioCrecidas(FuenteMemoria(archivosReales())), tamano: const Size(320, 640), oscuro: oscuro);
        expect(t.takeException(), isNull);
        final opcion = find.text('Ver todas');
        await t.scrollUntilVisible(opcion, 200, scrollable: find.byType(Scrollable).last);
        await t.tap(opcion);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}

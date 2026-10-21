/// Accesibilidad de la pestaña Mapa (docs/mapa/10-accesibilidad.md):
/// TalkBack (nodos, etiquetas, estado elegido, anuncios), pautas de Flutter
/// (toques de 48 dp, etiquetas, contraste), gestos que no atrapan la página,
/// alternativa a arrastrar y pellizcar, y movimiento reducido.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/mapa/estilo_mapa.dart';
import 'package:rio_paysandu/mapa/logica_mapa.dart';
import 'package:rio_paysandu/mapa/repositorio_mapa.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/mapa.dart';
import 'package:rio_paysandu/tema.dart';
import 'package:rio_paysandu/textos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures_mapa.dart';
import 'mapa_test.dart' show ahora, datosCon, lectura, mostrarMapa, tocar;

/// Junta los anuncios que la pantalla le manda a TalkBack.
List<String> escucharAnuncios(WidgetTester t) {
  final anuncios = <String>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
    final mapa = m as Map<Object?, Object?>;
    if (mapa['type'] == 'announce') anuncios.add((mapa['data'] as Map<Object?, Object?>)['message']! as String);
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
  );
  return anuncios;
}

/// Cámara del mapa (centro y zoom), leída desde adentro de flutter_map.
MapCamera camara(WidgetTester t) => MapCamera.of(t.element(find.byType(PolygonLayer).first));

double desplazamiento(WidgetTester t) => t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

void main() {
  group('TalkBack: nodos y etiquetas', () {
    testWidgets('la lectura es un nodo en palabras, sin liveRegion, y "Volver a hoy" va aparte', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      final nodo = find.bySemanticsLabel(
        'No es el río de hoy. Simulación con 4,30 metros, nivel Evacuación (de referencia). 10 centímetros más que hoy. '
        // 4,30 es la capa más alta del set de prueba: el margen queda recortado (I1).
        'El mapa llega hasta 4,30 metros: con un poco más de altura, el agua puede pasar los puntos y llegar más '
        'lejos de lo que se ve.',
      );
      expect(nodo, findsOneWidget);
      // Sin liveRegion: si no, TalkBack la repetiría en cada paso del arrastre.
      expect(t.getSemantics(nodo), isNot(isSemantics(isLiveRegion: true)));
      expect(
        find.bySemanticsLabel('Volver a hoy'),
        findsOneWidget,
        reason: 'el botón es un nodo propio, no queda mezclado en la lectura',
      );
      expect(t.getSemantics(find.bySemanticsLabel('Volver a hoy')), isSemantics(isButton: true, hasTapAction: true));
      s.dispose();
    });

    testWidgets('el deslizador tiene nombre, valor en metros y nivel', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      expect(
        t.getSemantics(find.byType(Slider)),
        isSemantics(
          label: textoDeslizador,
          value: '4,20 metros, nivel Alerta',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Marca de alerta: 4,15 metros (de referencia)'), findsOneWidget);
      s.dispose();
    });

    testWidgets('botones de altura: nombre, metros y "seleccionado" en el mismo nodo', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      expect(
        t.getSemantics(find.bySemanticsLabel('Hoy, 4,20 metros')),
        isSemantics(isButton: true, hasTapAction: true, hasSelectedState: true, isSelected: true),
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Nivel de evacuación, 4,28 metros (de referencia)')),
        isSemantics(isButton: true, hasTapAction: true, hasSelectedState: true, isSelected: false),
      );
      expect(find.bySemanticsLabel('Pronóstico CARU, hasta 6,66 metros, informe del 8/10'), findsOneWidget);
      await tocar(t, find.text('Crecida de prueba'));
      expect(
        t.getSemantics(find.bySemanticsLabel('Crecida de prueba, 4,25 metros')),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(t.getSemantics(find.bySemanticsLabel('Hoy, 4,20 metros')), isSemantics(isSelected: false));
      // El interruptor del borde medido: nombre y estado.
      expect(
        t.getSemantics(find.byType(Switch)),
        isSemantics(
          label: 'Ver el borde medido en esa crecida\nLínea de trazos sobre el mapa. Fuente: Dinagua.',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      s.dispose();
    });

    testWidgets('sello, mapa en palabras, zoom, flechas y pie se leen en orden', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      final etiquetas = <String>[];
      void recorrer(SemanticsNode n) {
        final d = n.getSemanticsData();
        final texto = d.label.isNotEmpty ? d.label : d.tooltip;
        if (texto.isNotEmpty) etiquetas.add(texto);
        n.visitChildren((h) {
          recorrer(h);
          return true;
        });
      }

      recorrer(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      int lugar(String inicio) => etiquetas.indexWhere((e) => e.startsWith(inicio));
      final orden = [
        'Río hoy: 4,13 metros',
        'Altura de hoy en el mapa: 4,20 metros',
        textoMapaEnPrueba,
        'Mapa de la costa de Paysandú',
        'Acercar',
        'Alejar',
        'Mover el mapa',
        'Ver más al oeste',
        'Ver más al norte',
        'Ver más al sur',
        'Ver más al este',
        textoAvisoMapa,
        'Probar otra altura',
        'Bajar 10 cm',
        textoDeslizador,
        'Subir 10 cm',
      ].map(lugar).toList();
      expect(orden, everyElement(greaterThanOrEqualTo(0)), reason: etiquetas.join('\n'));
      expect(orden, orderedEquals([...orden]..sort()), reason: etiquetas.join('\n'));
      // El mapa en palabras: altura dibujada, rayado, puntos y "puede llegar más lejos".
      final mapa = etiquetas[lugar('Mapa de la costa de Paysandú')];
      expect(mapa, contains('Agua dibujada con 4,20 metros: el rayado muestra hasta dónde llegaría.'));
      expect(mapa, contains('Los puntos, hasta dónde puede llegar con 10 centímetros más de altura.'));
      expect(mapa, contains('el agua puede llegar más lejos'));
      expect(mapa, isNot(contains('Simulación')));
      s.dispose();
    });
  });

  group('el mapa en palabras', () {
    test('cada situación tiene su resumen, y nunca promete que no llega', () {
      final casos = {
        'en rango, hoy': resumenMapa(
          situacion: SituacionAgua.enRango,
          alturaCm: 620,
          dibujoCm: 620,
          margenCm: 670,
          minCm: 400,
          maxCm: 1050,
        ),
        'simulación con borde medido': resumenMapa(
          situacion: SituacionAgua.enRango,
          alturaCm: 920,
          dibujoCm: 920,
          margenCm: 970,
          minCm: 400,
          maxCm: 1050,
          simulacion: true,
          contorno: 'Crecida de dic. 2015',
        ),
        'zona baja': resumenMapa(
          situacion: SituacionAgua.debajoDelMinimo,
          alturaCm: 390,
          dibujoCm: null,
          margenCm: 430,
          minCm: 400,
          maxCm: 1050,
        ),
        'sobre el máximo': resumenMapa(
          situacion: SituacionAgua.sobreMaximo,
          alturaCm: 1080,
          dibujoCm: 1050,
          margenCm: null,
          minCm: 400,
          maxCm: 1050,
        ),
        'dibujo ilegible': resumenMapa(
          situacion: SituacionAgua.enRango,
          alturaCm: 620,
          dibujoCm: null,
          margenCm: null,
          minCm: 400,
          maxCm: 1050,
          dibujoIlegible: true,
        ),
      };
      expect(casos['en rango, hoy'], contains('Agua dibujada con 6,20 metros'));
      expect(casos['en rango, hoy'], contains('con 50 centímetros más de altura'));
      expect(casos['simulación con borde medido'], contains('Simulación: no es el río de hoy.'));
      expect(casos['simulación con borde medido'], contains('borde medido en la crecida "Crecida de dic. 2015"'));
      expect(
        casos['zona baja'],
        contains(
          'Con 3,90 metros el agua no pasa de la zona baja de la costa: islas y bañados que se mojan con el río normal.',
        ),
      );
      expect(casos['zona baja'], isNot(contains('cauce')));
      expect(casos['sobre el máximo'], contains('Con 10,80 metros el agua llega más lejos de lo que se ve.'));
      expect(casos['dibujo ilegible'], contains('No se pudo leer el dibujo del agua'));
      for (final MapEntry(:key, :value) in casos.entries) {
        expect(value, contains('el agua puede llegar más lejos'), reason: key);
        expect(value, isNot(matches(RegExp(r'a salvo|\bsegur[oa]\b|no se inunda|sin peligro', caseSensitive: false))));
        expect(value, isNot(contains(' m ')), reason: 'unidades en palabras: $key');
      }
    });

    testWidgets('al simular, la descripción del mapa lo dice', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      await tocar(t, find.text('Crecida de prueba'));
      await tocar(t, find.byType(Switch));
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Mapa de la costa de Paysandú.*Simulación: no es el río de hoy\. Agua dibujada con 4,30 metros.*'
            r'borde medido en la crecida "Crecida de prueba"',
          ),
        ),
        findsOneWidget,
      );
      s.dispose();
    });
  });

  group('TalkBack: anuncios', () {
    testWidgets('un anuncio por cambio, que dice qué pasó con el agua', (t) async {
      final anuncios = escucharAnuncios(t);
      await mostrarMapa(t, datosCon(4.13));
      expect(anuncios, isEmpty, reason: 'al abrir no se anuncia nada');
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(anuncios, [
        'No es el río de hoy. Simulación con 4,30 metros, nivel Evacuación (de referencia). 10 centímetros más que hoy. '
            // 4,30 es la capa más alta del set de prueba: el margen queda recortado (I1).
            'El mapa llega hasta 4,30 metros: con un poco más de altura, el agua puede pasar los puntos y llegar más '
            'lejos de lo que se ve. '
            'El mapa ahora muestra el agua con 4,30 metros. Puede llegar más lejos.',
      ]);
      await tocar(t, find.text('Volver a hoy'));
      expect(anuncios.last, startsWith('Altura de hoy en el mapa: 4,20 metros.'));
      expect(anuncios.last, endsWith('El mapa ahora muestra el agua con 4,20 metros. Puede llegar más lejos.'));
    });

    testWidgets('arrastrando el deslizador no se anuncia nada hasta soltar', (t) async {
      final anuncios = escucharAnuncios(t);
      await mostrarMapa(t, datosCon(4.13));
      final barra = t.getRect(find.byType(Slider));
      final gesto = await t.startGesture(barra.center);
      await gesto.moveBy(Offset(-barra.width / 4, 0));
      await t.pumpAndSettle();
      await gesto.moveBy(Offset(-barra.width / 4, 0));
      await t.pumpAndSettle();
      expect(anuncios, isEmpty);
      await gesto.up();
      await t.pumpAndSettle();
      expect(anuncios, hasLength(1));
    });

    testWidgets('subir con TalkBack (acción del deslizador): un solo anuncio', (t) async {
      final s = t.ensureSemantics();
      final anuncios = escucharAnuncios(t);
      await mostrarMapa(t, datosCon(4.13));
      final nodo = t.getSemantics(find.byType(Slider));
      t.binding.renderViews.first.owner!.semanticsOwner!.performAction(nodo.id, SemanticsAction.decrease);
      await t.pumpAndSettle();
      expect(lectura('4,10'), findsOneWidget);
      expect(anuncios, hasLength(1));
      expect(anuncios.single, contains('Simulación con 4,10 metros'));
      s.dispose();
    });
  });

  group('gestos: el mapa no atrapa la página', () {
    // 360 × 800 dp. Se baja hasta el mapa (como haría la persona): con los
    // avisos de la lectura el mapa puede quedar más abajo de la primera vista.
    Future<void> abrir(WidgetTester t) async {
      await mostrarMapa(t, datosCon(4.13), tamano: const Size(720, 1600));
      await t.ensureVisible(find.byType(FlutterMap));
      await t.pumpAndSettle();
    }

    testWidgets('con un dedo sobre el mapa se mueve la página, no el mapa', (t) async {
      await abrir(t);
      final antes = camara(t).center;
      final paginaAntes = desplazamiento(t);
      final mapa = t.getRect(find.byType(FlutterMap));
      await t.dragFrom(mapa.center, const Offset(0, -200));
      await t.pumpAndSettle();
      expect(desplazamiento(t) - paginaAntes, greaterThan(100));
      expect(camara(t).center, antes);
    });

    testWidgets('arrastrar de costado con un dedo no mueve el mapa y dice cómo hacerlo', (t) async {
      await abrir(t);
      final antes = camara(t).center;
      await t.dragFrom(t.getRect(find.byType(FlutterMap)).center, const Offset(-120, 0));
      await t.pump();
      expect(camara(t).center, antes);
      expect(find.text(textoDosDedos), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      expect(find.text(textoDosDedos), findsNothing);
    });

    testWidgets('con dos dedos se acerca (pellizco)', (t) async {
      await abrir(t);
      final zoom = camara(t).zoom;
      final c = t.getRect(find.byType(FlutterMap)).center;
      final a = await t.startGesture(c - const Offset(30, 0), pointer: 1);
      final b = await t.startGesture(c + const Offset(30, 0), pointer: 2);
      for (var i = 0; i < 10; i++) {
        await a.moveBy(const Offset(-8, 0));
        await b.moveBy(const Offset(8, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await t.pumpAndSettle();
      expect(camara(t).zoom, greaterThan(zoom + 0.5));
    });

    testWidgets('sin arrastrar ni pellizcar: + / − y flechas de 48 dp', (t) async {
      await abrir(t);
      final zoom = camara(t).zoom;
      await tocar(t, find.byTooltip('Acercar'));
      expect(camara(t).zoom, zoom + 1);
      final antes = camara(t).center;
      await tocar(t, find.byTooltip('Ver más al norte'));
      expect(camara(t).center.latitude, greaterThan(antes.latitude));
      final medio = camara(t).center;
      await tocar(t, find.byTooltip('Ver más al oeste, hacia el río'));
      expect(camara(t).center.longitude, lessThan(medio.longitude));
      await tocar(t, find.byTooltip('Ver más al sur'));
      await tocar(t, find.byTooltip('Ver más al este'));
      expect(camara(t).center.latitude, closeTo(antes.latitude, 1e-6));
      expect(camara(t).center.longitude, closeTo(antes.longitude, 1e-6));
      for (final f in FilaMoverMapa.flechas) {
        expect(t.getSize(find.byTooltip(f.$2)), const Size(48, 48));
      }
    });
  });

  group('movimiento reducido', () {
    testWidgets('con "Quitar animaciones" el doble toque acerca sin animar', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      final normal = t.widget<FlutterMap>(find.byType(FlutterMap)).options.interactionOptions;
      expect(normal.doubleTapZoomDuration, greaterThan(Duration.zero));
      expect(InteractiveFlag.hasDrag(normal.flags), isFalse);
      expect(InteractiveFlag.hasFlingAnimation(normal.flags), isFalse);
      expect(InteractiveFlag.hasRotate(normal.flags), isFalse);

      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pumpAndSettle();
      final quieto = t.widget<FlutterMap>(find.byType(FlutterMap)).options.interactionOptions;
      expect(quieto.doubleTapZoomDuration, Duration.zero);
    });

    testWidgets('con "Quitar animaciones" la hoja de fuentes aparece de una', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await mostrarMapa(t, datosCon(4.13));
      await t.ensureVisible(find.text('Ver fuentes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ver fuentes'));
      await t.pump(); // arma la ruta
      await t.pump(); // primer cuadro: ya en su lugar, sin deslizarse
      final hoja = t.getRect(find.byType(BottomSheet));
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(BottomSheet)), hoja);
    });
  });

  group('pautas de Android y WCAG', () {
    for (final escala in [1.0, 1.3, 2.0]) {
      for (final oscuro in [false, true]) {
        testWidgets(
          '320 dp, letra ${(escala * 100).round()} %${oscuro ? ', oscuro' : ''}: 48 dp, etiquetas y contraste',
          (t) async {
            Colores.oscuro = oscuro;
            addTearDown(() => Colores.oscuro = false);
            t.platformDispatcher.textScaleFactorTestValue = escala;
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            final s = t.ensureSemantics();
            SharedPreferences.setMockInitialValues({});
            final prefs = await SharedPreferences.getInstance();
            // Alto de sobra: toda la pantalla queda a la vista y se mide entera.
            final tamano = Size(640, 4400 * escala * 1.6);
            for (final (nombre, datos, cuando, simular) in [
              ('hoy en alerta, con "Cómo se usa"', datosCon(4.13), ahora, false),
              ('simulación con crecida y borde', datosCon(6.95, nivel: 'evacuacion'), ahora, true),
              ('sin dato', datosCon(null, nivel: 'sin_dato'), ahora, false),
              ('dato viejo', datosCon(4.13), ahora.add(const Duration(hours: 9)), false),
            ]) {
              await mostrarMapa(
                t,
                datos,
                cuando: cuando,
                prefs: prefs,
                alVerQueHacer: () {},
                repositorio: RepositorioMapa(fuenteDePrueba()),
                tamano: tamano,
              );
              if (simular) {
                await tocar(t, find.text('Crecida de prueba'));
                await tocar(t, find.byType(Switch));
                await t.ensureVisible(find.byType(LecturaMapa));
                await t.pumpAndSettle();
              }
              expect(t.takeException(), isNull, reason: nombre);
              await expectLater(t, meetsGuideline(androidTapTargetGuideline), reason: nombre);
              await expectLater(t, meetsGuideline(labeledTapTargetGuideline), reason: nombre);
              await expectLater(t, meetsGuideline(textContrastGuideline), reason: nombre);
            }
            s.dispose();
          },
        );
      }
    }
  });

  group('contraste de colores propios de la pantalla', () {
    tearDown(() => Colores.oscuro = false);

    test('pista vacía del deslizador: 3:1 contra el fondo y la tarjeta; se distingue de la llena', () {
      for (final oscuro in [false, true]) {
        Colores.oscuro = oscuro;
        expect(
          contraste(ColoresDeslizador.pistaVacia, Colores.fondo),
          greaterThanOrEqualTo(3),
          reason: 'oscuro=$oscuro',
        );
        expect(contraste(Colores.primario, Colores.fondo), greaterThanOrEqualTo(3));
        expect(contraste(ColoresDeslizador.pistaVacia, Colores.primario), greaterThanOrEqualTo(2.5));
      }
    });

    test('textos sobre el tinte de hoy y botones de la grilla: 4,5:1 o más', () {
      for (final oscuro in [false, true]) {
        Colores.oscuro = oscuro;
        for (final n in Nivel.values) {
          final tinte = ColoresNivel.tinte(n);
          for (final texto in [Colores.tinta, Colores.tintaSecundaria, Colores.primario, ColoresNivel.familia(n)]) {
            expect(contraste(texto, tinte), greaterThanOrEqualTo(4.5), reason: '$n oscuro=$oscuro');
          }
        }
        // Botón elegido (relleno) y sin elegir (borde y texto sobre el fondo).
        expect(contraste(Colores.sobrePrimario, Colores.primario), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.primario, Colores.fondo), greaterThanOrEqualTo(4.5));
      }
    });

    test('pastilla de nivel, sello ámbar y panel invertido', () {
      for (final oscuro in [false, true]) {
        Colores.oscuro = oscuro;
        for (final n in [Nivel.atencion, Nivel.alerta, Nivel.evacuacion]) {
          final e = estiloNivel(n);
          expect(contraste(e.texto, e.fondo), greaterThanOrEqualTo(4.5), reason: '$n oscuro=$oscuro');
        }
        final ambar = oscuro ? const Color(0xFF3A2E12) : const Color(0xFFFFF4D6);
        final iconoAmbar = oscuro ? const Color(0xFFFFC857) : const Color(0xFF7A4A00);
        expect(contraste(Colores.tinta, ambar), greaterThanOrEqualTo(7));
        expect(contraste(iconoAmbar, ambar), greaterThanOrEqualTo(3));
        expect(contraste(ColoresSimulacion.texto, ColoresSimulacion.fondo), greaterThanOrEqualTo(7));
      }
    });

    test('muestras de la leyenda sobre el fondo de la app: bordes de 3:1 o más', () {
      for (final (oscuro, c) in [(false, ColoresMapa.claro), (true, ColoresMapa.noche)]) {
        Colores.oscuro = oscuro;
        for (final borde in [c.orilla, c.bordeAgua, c.bordeMargen, c.contorno]) {
          expect(contraste(borde, Colores.fondo), greaterThanOrEqualTo(3), reason: 'oscuro=$oscuro $borde');
        }
      }
    });
  });
}

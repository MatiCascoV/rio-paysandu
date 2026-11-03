/// Pantalla de primer arranque (P-04): una sola vez, solo en instalaciones nuevas,
/// y sin pedir permiso ni suscribir nada hasta que la persona elige.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:rio_paysandu/pantallas/ajustes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = Config(urlBase: 'https://ejemplo.test/data/');

class ControlFalso implements ControlAvisos {
  bool darPermiso = true;
  int pedidos = 0;
  int aplicados = 0;
  int sincronizados = 0;
  final temasSuscritos = <String>{};

  @override
  Future<bool?> permitidas() async => true;

  @override
  Future<bool> pedirPermiso() async {
    pedidos++;
    return darPermiso;
  }

  @override
  Future<void> aplicar(SharedPreferences prefs) async => aplicados++;

  @override
  Future<bool> sincronizarTemas(SharedPreferences prefs) async {
    sincronizados++;
    temasSuscritos
      ..clear()
      ..addAll(temasDeseados(PreferenciasAvisos.leer(prefs)));
    return true;
  }

  @override
  bool get pushDisponible => true;
}

/// Como main(): decide el primer arranque con las preferencias que había, y arma la app sin conexión.
Future<(SharedPreferences, ControlFalso)> abrirApp(
  WidgetTester t,
  Map<String, Object> valores, {
  ControlFalso? control,
  double letra = 1.0,
}) async {
  t.view.physicalSize = const Size(720, 1480); // 360 x 740 dp
  t.view.devicePixelRatio = 2.0;
  t.platformDispatcher.textScaleFactorTestValue = letra;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues(valores);
  final prefs = await SharedPreferences.getInstance();
  await prepararPrimerArranque(prefs);
  final c = control ?? ControlFalso();
  // Sin conexión: toda la red falla.
  final sinRed = MockClient((_) async => throw http.ClientException('sin red'));
  await t.pumpWidget(
    RioPaysanduApp(
      config: config,
      prefs: prefs,
      repositorio: Repositorio(config.urlBase, cliente: sinRed),
      control: c,
    ),
  );
  await t.pumpAndSettle();
  return (prefs, c);
}

Future<void> cerrar(WidgetTester t) => t.pumpWidget(const SizedBox()); // detiene el reloj de la app

void main() {
  testWidgets('primer arranque: se ve la pantalla, con todo apagado y nada pedido ni suscrito', (t) async {
    final (prefs, c) = await abrirApp(t, {});
    expect(find.text('¿Querés avisos de crecida?'), findsOneWidget);
    expect(find.text('Activar avisos'), findsOneWidget);
    expect(find.text('Ahora no'), findsOneWidget);
    expect(find.text('Política de privacidad'), findsOneWidget);
    // Los textos nuevos (P-03): identificador anónimo desde que se abre la app, y qué quita apagar.
    expect(find.textContaining('identificador anónimo desde que se abre la app'), findsOneWidget);
    expect(find.textContaining('Apagar los avisos quita las suscripciones'), findsOneWidget);
    expect(find.textContaining('el identificador sigue hasta que desinstales la app'), findsOneWidget);
    expect(find.textContaining('la alerta oficial la dan el Sinae y el Cecoed'), findsOneWidget);
    // Hasta que elige: el resumen NO viene prendido, no se pidió permiso ni se suscribió nada.
    final p = PreferenciasAvisos.leer(prefs);
    expect(p.urgente, isFalse);
    expect(p.resumen, isFalse);
    expect(temasDeseados(p), isEmpty);
    expect(c.pedidos, 0);
    expect(c.sincronizados, 0);
    expect(t.takeException(), isNull);
    await cerrar(t);
  });

  testWidgets('"Activar avisos" prende el urgente desde alerta y el resumen, y recién ahí pide permiso y suscribe', (
    t,
  ) async {
    final (prefs, c) = await abrirApp(t, {});
    await t.tap(find.text('Activar avisos'));
    await t.pumpAndSettle();
    expect(c.pedidos, 1);
    expect(c.aplicados, 1);
    expect(c.sincronizados, 1);
    expect(prefs.getBool(claveUrgente), isTrue);
    expect(prefs.getString(claveUrgenteDesde), 'alerta');
    expect(prefs.getBool(claveResumen), isTrue);
    expect(c.temasSuscritos, {'alerta-paysandu', 'resumen-paysandu'});
    expect(prefs.getString(clavePrimerArranque), primerArranqueHecho);
    // Pasó a la app, sin conexión pero sin nada raro.
    expect(find.text('¿Querés avisos de crecida?'), findsNothing);
    expect(find.text('Avisos'), findsWidgets);
    expect(t.takeException(), isNull);
    await cerrar(t);
  });

  testWidgets('"Ahora no" deja todo apagado y no suscribe a ningún tema ni pide permiso', (t) async {
    final (prefs, c) = await abrirApp(t, {});
    await t.tap(find.text('Ahora no'));
    await t.pumpAndSettle();
    expect(c.pedidos, 0);
    expect(c.sincronizados, 0);
    expect(c.temasSuscritos, isEmpty);
    expect(prefs.getBool(claveUrgente), isFalse);
    expect(prefs.getBool(claveResumen), isFalse);
    expect(temasDeseados(PreferenciasAvisos.leer(prefs)), isEmpty);
    expect(prefs.getString(clavePrimerArranque), primerArranqueHecho);
    expect(find.text('¿Querés avisos de crecida?'), findsNothing);
    expect(t.takeException(), isNull);
    await cerrar(t);
  });

  testWidgets('si se niega el permiso, queda todo apagado y sin suscripción, y se puede seguir', (t) async {
    final (prefs, c) = await abrirApp(t, {}, control: ControlFalso()..darPermiso = false);
    await t.tap(find.text('Activar avisos'));
    await t.pumpAndSettle();
    expect(c.pedidos, 1);
    expect(c.sincronizados, 0);
    expect(prefs.getBool(claveUrgente), isFalse);
    expect(prefs.getBool(claveResumen), isFalse);
    expect(find.textContaining('No diste permiso'), findsOneWidget);
    await t.tap(find.text('Seguir'));
    await t.pumpAndSettle();
    expect(find.text('¿Querés avisos de crecida?'), findsNothing);
    await cerrar(t);
  });

  testWidgets('segunda apertura: ya eligió, no vuelve a mostrar la pantalla', (t) async {
    final (prefs, _) = await abrirApp(t, {});
    await t.tap(find.text('Ahora no'));
    await t.pumpAndSettle();
    await cerrar(t);
    // "Cerrar y volver a abrir la app" con las mismas preferencias guardadas.
    await prepararPrimerArranque(prefs);
    expect(debeMostrarPrimerArranque(prefs), isFalse);
    final c2 = ControlFalso();
    final sinRed = MockClient((_) async => throw http.ClientException('sin red'));
    await t.pumpWidget(
      RioPaysanduApp(
        config: config,
        prefs: prefs,
        repositorio: Repositorio(config.urlBase, cliente: sinRed),
        control: c2,
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('¿Querés avisos de crecida?'), findsNothing);
    expect(find.text('Activar avisos'), findsNothing);
    await cerrar(t);
  });

  testWidgets('si cierra la app sin elegir, la pantalla vuelve (todavía no eligió)', (t) async {
    final (prefs, _) = await abrirApp(t, {});
    await cerrar(t);
    await prepararPrimerArranque(prefs); // idempotente: no la da por hecha
    expect(debeMostrarPrimerArranque(prefs), isTrue);
    expect(prefs.getBool(claveResumen), isFalse);
  });

  group('instalación existente: no ve la pantalla ni cambia nada', () {
    final casos = <String, Map<String, Object>>{
      'con avisos ya migrados y el resumen prendido': {claveVersionAvisos: 1, claveUrgente: false, claveResumen: true},
      'con el urgente prendido': {claveVersionAvisos: 1, claveUrgente: true, claveResumen: false},
      'con el resumen apagado a mano': {claveVersionAvisos: 1, claveUrgente: false, claveResumen: false},
      'de la versión vieja, sin migrar': {claveViejaActivos: true, claveViejaDesde: 'atencion'},
      'que solo tiene la dirección de datos y el modo oscuro': {
        claveUrl: 'https://ejemplo.test/data/',
        'tema': 'oscuro',
      },
    };
    for (final MapEntry(key: nombre, value: valores) in casos.entries) {
      testWidgets(nombre, (t) async {
        final antes = PreferenciasAvisos.leer(await _prefsCon(valores));
        final (prefs, c) = await abrirApp(t, valores);
        expect(find.text('¿Querés avisos de crecida?'), findsNothing);
        expect(find.text('Activar avisos'), findsNothing);
        expect(prefs.getString(clavePrimerArranque), primerArranqueHecho);
        // Las preferencias de avisos quedan como estaban.
        final despues = PreferenciasAvisos.leer(prefs);
        expect(despues.urgente, antes.urgente);
        expect(despues.resumen, antes.resumen);
        expect(despues.desde, antes.desde);
        expect(c.pedidos, 0);
        expect(c.sincronizados, 0);
        await cerrar(t);
      });
    }
  });

  testWidgets('con letra al 200 % y 320 dp de ancho no desborda y los botones se alcanzan', (t) async {
    t.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
    await abrirApp(t, {}, letra: 2.0);
    t.view.physicalSize = const Size(640, 1136);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Ahora no'));
    expect(find.text('Activar avisos'), findsOneWidget);
    // Botones grandes: al menos 48 dp de alto (accesibilidad táctil).
    expect(t.getSize(find.widgetWithText(FilledButton, 'Activar avisos')).height, greaterThanOrEqualTo(48));
    expect(t.getSize(find.widgetWithText(OutlinedButton, 'Ahora no')).height, greaterThanOrEqualTo(48));
    await cerrar(t);
  });

  testWidgets('Avisos dice con veracidad lo del identificador anónimo de Firebase', (t) async {
    final (_, _) = await abrirApp(t, {claveVersionAvisos: 1, claveUrgente: false, claveResumen: false});
    await t.tap(find.text('Avisos'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.textContaining('identificador anónimo'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('identificador anónimo desde que se abre la app'), findsOneWidget);
    expect(find.textContaining('Apagar los avisos quita las suscripciones'), findsOneWidget);
    expect(find.textContaining('el identificador sigue hasta que desinstales la app'), findsOneWidget);
    await cerrar(t);
  });
}

Future<SharedPreferences> _prefsCon(Map<String, Object> valores) async {
  SharedPreferences.setMockInitialValues(valores);
  return SharedPreferences.getInstance();
}

/// Pestaña Avisos: aviso urgente (desde alerta o solo evacuación) y resumen del día.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/ajustes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';

class ControlFalso implements ControlAvisos {
  bool? permitidasAhora = true;
  bool darPermiso = true;
  bool fallaAplicar = false;
  bool sincronizaBien = true;
  int pedidos = 0;
  int aplicados = 0;
  int sincronizados = 0;

  @override
  Future<bool?> permitidas() async => permitidasAhora;

  @override
  Future<bool> pedirPermiso() async {
    pedidos++;
    permitidasAhora = darPermiso;
    return darPermiso;
  }

  @override
  Future<void> aplicar(SharedPreferences prefs) async {
    if (fallaAplicar) throw Exception('workmanager');
    aplicados++;
  }

  @override
  Future<bool> sincronizarTemas(SharedPreferences prefs) async {
    sincronizados++;
    if (sincronizaBien) await prefs.setString('temas_al_dia', firmaTemas(temasDeseados(PreferenciasAvisos.leer(prefs))));
    return sincronizaBien;
  }

  @override
  bool get pushDisponible => true;
}

final umbrales = Umbrales.desdeJson(jsonDecode(umbralesReal));

Future<(SharedPreferences, ControlFalso)> mostrar(WidgetTester t, Map<String, Object> valores,
    {ControlFalso? control}) async {
  t.view.physicalSize = const Size(1080, 6000);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(valores);
  final prefs = await SharedPreferences.getInstance();
  final c = control ?? ControlFalso();
  await t.pumpWidget(MaterialApp(
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: PantallaAjustes(prefs: prefs, datos: Datos(umbrales: umbrales), control: c)),
  ));
  await t.pumpAndSettle();
  return (prefs, c);
}

bool prendido(WidgetTester t, String titulo) =>
    t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, titulo)).value;

const urgente = 'Recibir el aviso urgente';
const resumen = 'Recibir el resumen';
const bloqueadas = 'Las notificaciones de esta app están bloqueadas';

void main() {
  testWidgets('instalación nueva: urgente apagado, resumen prendido, y los textos que aclaran', (t) async {
    await mostrar(t, {});
    expect(prendido(t, urgente), isFalse);
    expect(prendido(t, resumen), isTrue);
    expect(find.text('Desde alerta'), findsOneWidget);
    expect(find.text('Solo evacuación'), findsOneWidget);
    // Con el urgente apagado no se puede elegir.
    expect(t.widget<RadioListTile<Nivel>>(find.widgetWithText(RadioListTile<Nivel>, 'Desde alerta')).enabled, isFalse);
    expect(find.textContaining('con el río normal no llega nada'), findsOneWidget);
    expect(find.textContaining('no reemplazan la alerta oficial: la dan el Sinae y el Cecoed'), findsOneWidget);
    expect(find.textContaining('Firebase Cloud Messaging'), findsOneWidget);
    expect(find.textContaining('identificador anónimo'), findsOneWidget);
    expect(find.textContaining(bloqueadas), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('los metros de cada opción salen de umbrales.json', (t) async {
    await mostrar(t, {});
    expect(find.text('Avisa al subir a alerta (4,39 m) y a evacuación (6,89 m).'), findsOneWidget);
    expect(find.text('Avisa solo al subir a evacuación (6,89 m).'), findsOneWidget);
  });

  testWidgets('prender el urgente pide permiso, guarda, programa y sincroniza; después se elige', (t) async {
    final (prefs, c) = await mostrar(t, {});
    await t.tap(find.text(urgente));
    await t.pumpAndSettle();
    expect(c.pedidos, 1);
    expect(prefs.getBool(claveUrgente), isTrue);
    expect(c.aplicados, 1);
    expect(c.sincronizados, 1);
    expect(prendido(t, urgente), isTrue);

    await t.tap(find.text('Solo evacuación'));
    await t.pumpAndSettle();
    expect(prefs.getString(claveUrgenteDesde), 'evacuacion');
    expect(c.sincronizados, 2);

    // Apagar el resumen no pide permiso.
    await t.tap(find.text(resumen));
    await t.pumpAndSettle();
    expect(prefs.getBool(claveResumen), isFalse);
    expect(c.pedidos, 1);
    expect(prendido(t, resumen), isFalse);
  });

  testWidgets('si se niega el permiso, queda apagado y se explica cómo arreglarlo', (t) async {
    final (prefs, _) = await mostrar(t, {}, control: ControlFalso()..darPermiso = false);
    await t.tap(find.text(urgente));
    await t.pumpAndSettle();
    expect(prefs.getBool(claveUrgente), isNot(isTrue));
    expect(prendido(t, urgente), isFalse);
    expect(find.textContaining(bloqueadas), findsOneWidget);
    // Y el resumen, que estaba prendido, tampoco se muestra prendido: no va a llegar.
    expect(prendido(t, resumen), isFalse);
  });

  testWidgets('con las notificaciones bloqueadas nada se muestra prendido', (t) async {
    await mostrar(t, {claveVersionAvisos: 1, claveUrgente: true, claveResumen: true},
        control: ControlFalso()..permitidasAhora = false);
    expect(prendido(t, urgente), isFalse);
    expect(prendido(t, resumen), isFalse);
    expect(find.textContaining(bloqueadas), findsOneWidget);
  });

  testWidgets('si la revisión no se puede programar, el interruptor vuelve a apagado', (t) async {
    final (prefs, _) = await mostrar(t, {}, control: ControlFalso()..fallaAplicar = true);
    await t.tap(find.text(urgente));
    await t.pumpAndSettle();
    expect(prefs.getBool(claveUrgente), isNot(isTrue));
    expect(prendido(t, urgente), isFalse);
    expect(find.textContaining('No se pudieron cambiar los avisos'), findsOneWidget);
  });

  testWidgets('sin conexión los temas quedan pendientes y se avisa sin trabar', (t) async {
    final (prefs, _) = await mostrar(t, {}, control: ControlFalso()..sincronizaBien = false);
    await t.tap(find.text(urgente));
    await t.pumpAndSettle();
    expect(prefs.getBool(claveUrgente), isTrue);
    expect(prendido(t, urgente), isTrue);
    expect(find.textContaining('se terminan de activar cuando el teléfono tenga conexión'), findsOneWidget);
  });

  testWidgets('las preferencias viejas se ven migradas', (t) async {
    await mostrar(t, {'avisos_activos': true, 'avisar_desde': 'evacuacion'});
    expect(prendido(t, urgente), isTrue);
    expect(prendido(t, resumen), isTrue);
    final grupo = t.widget<RadioGroup<Nivel>>(find.byType(RadioGroup<Nivel>));
    expect(grupo.groupValue, Nivel.evacuacion);
  });

  testWidgets('ayuda plegable para cuando no llegan los avisos', (t) async {
    await mostrar(t, {});
    expect(find.textContaining('Inicio automático'), findsNothing);
    await t.tap(find.text('¿No te llegan los avisos?'));
    await t.pumpAndSettle();
    expect(find.textContaining('Inicio automático'), findsOneWidget);
    expect(find.textContaining('Sin restricciones'), findsOneWidget);
  });

  testWidgets('con el urgente prendido dice cuándo llega el próximo aviso', (t) async {
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({claveVersionAvisos: 1, claveUrgente: true, claveUrgenteDesde: 'alerta'});
    final prefs = await SharedPreferences.getInstance();
    final j = actualFalso('atencion', 4.10);
    (j['altura_actual'] as Map)['fecha'] = DateTime.now().toUtc().toIso8601String();
    j['generado'] = DateTime.now().toUtc().toIso8601String();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PantallaAjustes(
            prefs: prefs, datos: Datos(actual: Actual.desdeJson(j), umbrales: umbrales), control: ControlFalso()),
      ),
    ));
    await t.pumpAndSettle();
    expect(
        find.text('Ahora el río está en nivel ATENCIÓN (4,10 m). El próximo aviso urgente llega si sube a alerta (4,39 m).'),
        findsOneWidget);
  });
}

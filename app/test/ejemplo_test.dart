/// Los datos de ejemplo (DATOS_EJEMPLO) no pueden dejar rastro: ni copia
/// guardada que después se muestre como real, ni avisos inventados.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/ejemplo.dart';
import 'package:rio_paysandu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = Config(urlBase: 'https://ejemplo.test/data/');
const canalAvisos = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  final llamadas = <String>[];
  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith(); // el plugin de verdad, con su canal simulado
    llamadas.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalAvisos, (m) async {
      llamadas.add(m.method);
      return null;
    });
  });
  tearDown(() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canalAvisos, null));

  /// Preferencias de la versión anterior (avisos prendidos desde alerta), con el
  /// río en normal la última vez: si se revisa el nivel, sale un aviso urgente.
  const iniciales = {'avisos_activos': true, 'avisar_desde': 'alerta', 'ultimo_nivel': 'normal', 'tema': 'claro'};

  /// Abre la app con [repositorio] y devuelve las claves guardadas al final.
  Future<Map<String, Object>> abrirApp(WidgetTester t, Repositorio repositorio) async {
    SharedPreferences.setMockInitialValues(iniciales);
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(RioPaysanduApp(config: config, prefs: prefs, repositorio: repositorio));
    await t.pumpAndSettle();
    expect(find.text('ALERTA'), findsOneWidget);
    await prefs.reload();
    final claves = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    await t.pumpWidget(const SizedBox()); // detiene el reloj de la app
    return claves;
  }

  testWidgets('con datos de ejemplo no se guarda nada ni se avisa', (t) async {
    final claves = await abrirApp(
        t, Repositorio(config.urlBase, cliente: clienteDeEjemplo('alerta'), soloLectura: true));
    expect(claves, iniciales);
    // La pestaña Avisos solo pregunta si las notificaciones están permitidas.
    expect(llamadas.where((m) => m != 'areNotificationsEnabled'), isEmpty);
  });

  testWidgets('control: con un repositorio normal los mismos datos sí se guardan y se avisa', (t) async {
    final claves = await abrirApp(t, Repositorio(config.urlBase, cliente: clienteDeEjemplo('alerta')));
    expect(claves.keys, containsAll(['cache_actual', 'cache_umbrales', 'cache_historial', 'ultimo_nivel']));
    expect(llamadas, contains('show'));
  });

  test('una compilación sin DATOS_EJEMPLO no usa datos de ejemplo', () {
    expect(nivelDeEjemplo(), isNull);
  });
}

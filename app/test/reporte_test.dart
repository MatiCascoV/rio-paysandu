import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/ajustes.dart';
import 'package:rio_paysandu/reporte.dart';
import 'package:shared_preferences/shared_preferences.dart';

DatosReporte _datos({Lectura? l, bool? viejo}) => DatosReporte(
      version: '1.0.0',
      build: '7',
      androidVersion: 'Linux 5.10 #1 SMP',
      ahora: DateTime.utc(2026, 11, 6, 17, 5),
      ultimaLectura: l,
      desactualizado: viejo,
      avisoUrgente: true,
      resumenDelDia: false,
    );

String _cuerpo(DatosReporte d) => Uri.splitQueryString(armarMailto(d).query)['body']!;

void main() {
  test('el mailto va al correo definido, con espacios como %20 y sin "+"', () {
    final u = armarMailto(_datos());
    final t = u.toString();
    expect(u.scheme, 'mailto');
    expect(t, startsWith('mailto:mcasco.paysandu@gmail.com?subject='));
    expect(t, isNot(contains('+')));
    expect(t, isNot(contains(' ')));
    expect(t, contains('%20'));
    expect(t, contains('&body='));
    expect(Uri.splitQueryString(u.query)['subject'], 'Mi Río UY: problema con la app (v1.0.0)');
  });

  test('el cuerpo tiene primero el texto para escribir y después los datos técnicos', () {
    final cuerpo = _cuerpo(_datos());
    expect(cuerpo, startsWith('Contanos qué pasó (¿el dato está viejo, no coincide con CARU, falló algo?):'));
    expect(cuerpo, contains('Datos técnicos (podés borrarlos):'));
    expect(cuerpo, contains('App: 1.0.0 (build 7)'));
    expect(cuerpo, contains('Android: Linux 5.10 #1 SMP'));
    expect(cuerpo, contains('Avisos: urgente sí, resumen no'));
    expect(cuerpo, contains('Último dato mostrado: sin dato'));
    expect(cuerpo.indexOf('Contanos'), lessThan(cuerpo.indexOf('Datos técnicos')));
  });

  test('un "+" o "&" en los datos no rompe el mailto', () {
    final d = DatosReporte(
      version: '1.0.0+1',
      build: '1',
      androidVersion: 'a&b=c',
      ahora: DateTime.utc(2026, 1, 1),
      avisoUrgente: false,
      resumenDelDia: true,
    );
    final q = Uri.splitQueryString(armarMailto(d).query);
    expect(q['subject'], 'Mi Río UY: problema con la app (v1.0.0+1)');
    expect(q['body'], contains('Android: a&b=c'));
  });

  test('el último dato dice si estaba desactualizado', () {
    final l = Lectura(valorM: 3.5, fecha: DateTime.utc(2026, 11, 6, 12));
    expect(_cuerpo(_datos(l: l, viejo: true)), contains('3,50 m (marcado como desactualizado)'));
    expect(_cuerpo(_datos(l: l, viejo: false)), contains('3,50 m (no marcado como desactualizado)'));
  });

  test('DatosReporte.desde marca desactualizado según la antigüedad de la lectura', () {
    final ahora = DateTime.utc(2026, 11, 6, 12);
    final avisos = const PreferenciasAvisos();
    DatosReporte armar(DateTime fecha) => DatosReporte.desde(
          version: '1',
          build: '1',
          androidVersion: 'x',
          ahora: ahora,
          actual: Actual(altura: Lectura(valorM: 3, fecha: fecha), nivel: Nivel.normal),
          avisos: avisos,
        );
    expect(armar(ahora.subtract(const Duration(hours: 1))).desactualizado, false);
    expect(armar(ahora.subtract(const Duration(hours: 60))).desactualizado, true);
  });

  test('no incluye nada que identifique al teléfono o a la persona', () {
    final cuerpo = _cuerpo(_datos()).toLowerCase();
    for (final p in ['token', 'fcm', 'installation', 'imei', 'ubicaci', 'modelo', 'advertising']) {
      expect(cuerpo, isNot(contains(p)), reason: p);
    }
  });

  test('la fecha lleva la zona del teléfono', () {
    expect(fechaConZona(DateTime.now()), matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d \(UTC[+-]\d\d:\d\d\)$')));
  });

  group('botón en Avisos', () {
    Future<List<Uri>> montar(WidgetTester t, {required bool abre}) async {
      t.view.physicalSize = const Size(1080, 6000);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lanzados = <Uri>[];
      await t.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: PantallaAjustes(
            prefs: prefs,
            datos: const Datos(),
            control: _Falso(),
            leerVersion: () async => (version: '2.3.4', build: '9'),
            abrirCorreo: (u) async {
              lanzados.add(u);
              return abre;
            },
          ),
        ),
      ));
      await t.pumpAndSettle();
      return lanzados;
    }

    testWidgets('abre el correo con la versión inyectada', (t) async {
      final lanzados = await montar(t, abre: true);
      expect(find.text('¿Algo no anda bien?'), findsOneWidget);
      expect(find.textContaining('No se envía nada solo.'), findsOneWidget);
      expect(find.text('También podés avisar en GitHub (hace falta cuenta)'), findsOneWidget);
      await t.tap(find.text('Reportar un problema'));
      await t.pumpAndSettle();
      expect(lanzados, hasLength(1));
      expect(Uri.splitQueryString(lanzados.single.query)['subject'], contains('(v2.3.4)'));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('sin app de correo muestra la dirección para copiar', (t) async {
      String? copiado;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await montar(t, abre: false);
      await t.tap(find.text('Reportar un problema'));
      await t.pumpAndSettle();
      expect(find.text('No encontramos una app de correo. Escribinos a'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      await t.tap(find.text('Copiar dirección'));
      await t.pumpAndSettle();
      expect(copiado, correoReportes);
    });
  });
}

class _Falso implements ControlAvisos {
  @override
  Future<bool?> permitidas() async => true;
  @override
  Future<bool> pedirPermiso() async => true;
  @override
  Future<void> aplicar(SharedPreferences prefs) async {}
  @override
  Future<bool> sincronizarTemas(SharedPreferences prefs) async => true;
  @override
  bool get pushDisponible => true;
}

/// Muestra los avisos en el teléfono y programa la revisión local de respaldo.
///
/// Los avisos llegan por push (push.dart): el teléfono recibe un mensaje sin
/// texto, baja actual.json y arma la notificación. Por si el push no llega (sin
/// servicios de Google, restricciones del fabricante), la app también revisa el
/// nivel al abrirse y, si Android lo permite, cada 30 minutos en segundo plano,
/// con las mismas reglas y las mismas marcas (ver avisos.dart).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'avisos.dart';
import 'datos.dart';
import 'modelos.dart';

const _tarea = 'chequeo_nivel';

/// Versión del pedido de permiso al abrir: se pide una vez por instalación o
/// actualización que lo necesite (se sube el número si hace falta volver a pedirlo).
const clavePermisoPedido = 'permiso_avisos_pedido';
const _versionPermiso = 1;

final _plugin = FlutterLocalNotificationsPlugin();

Future<void> iniciarPlugin() => _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notificacion')),
    );

AndroidFlutterLocalNotificationsPlugin? get _android =>
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

/// Muestra un aviso. Cada tipo usa siempre la misma notificación: un aviso
/// nuevo reemplaza al anterior del mismo tipo (y el urgente de verdad, al
/// genérico "hay novedades").
Future<void> mostrarAviso(Aviso aviso) {
  final urgente = aviso.tipo == TipoAviso.urgente;
  final estilo = BigTextStyleInformation(aviso.texto);
  return _plugin.show(
    id: urgente ? 1 : 2,
    title: aviso.titulo,
    body: aviso.texto,
    notificationDetails: NotificationDetails(
      android: urgente
          // El canal es el de la versión anterior: Android no deja bajarle la importancia a uno existente.
          ? AndroidNotificationDetails(
              'nivel_rio',
              'Aviso urgente',
              channelDescription: 'Cuando el río Uruguay en Paysandú sube a alerta o a evacuación',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: estilo,
            )
          : AndroidNotificationDetails(
              'resumen_dia',
              'Resumen del día',
              channelDescription: 'Una vez por día, solo con el río en atención o más',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              styleInformation: estilo,
            ),
    ),
  );
}

/// Revisa el nivel con las reglas compartidas y muestra lo que corresponda.
/// [origen]: [Origen.app] si la app está a la vista (el resumen no se notifica).
Future<void> revisarNivel(Actual? actual, SharedPreferences prefs,
    {DateTime? ahora, Origen origen = Origen.respaldo}) async {
  if (kIsWeb || actual == null) return;
  for (final aviso in await decidirAvisos(actual, prefs, ahora ?? DateTime.now(), origen: origen)) {
    await mostrarAviso(aviso);
  }
}

/// Punto de entrada de la tarea en segundo plano (la llama Android, no la app).
@pragma('vm:entry-point')
void tareaEnSegundoPlano() {
  Workmanager().executeTask((tarea, datosDeEntrada) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(claveUrl);
      if (url == null) return true;
      await iniciarPlugin();
      final datos = await Repositorio(url).cargar(soloActual: true);
      if (!datos.sinConexion) await revisarNivel(datos.actual, prefs);
    } catch (_) {
      // Si falla, se reintenta en la próxima pasada.
    }
    return true;
  });
}

class Notificaciones {
  /// Se llama una vez al abrir la app.
  static Future<void> iniciar(Config config, SharedPreferences prefs) async {
    if (kIsWeb) return;
    await prefs.setString(claveUrl, config.urlBase);
    await prefs.setInt(claveHorasSinDato, config.horasSinDato);
    await migrarPreferencias(prefs);
    await iniciarPlugin();
    await Workmanager().initialize(tareaEnSegundoPlano);
    await aplicar(prefs);
  }

  static Future<void> _programar() => Workmanager().registerPeriodicTask(
        _tarea,
        _tarea,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  /// Programa la revisión de respaldo si hay algún aviso prendido (urgente o
  /// resumen) y la cancela si no. Si no se puede programar, lanza la excepción.
  static Future<void> aplicar(SharedPreferences prefs) async {
    if (kIsWeb) return;
    if (PreferenciasAvisos.leer(prefs).algunoPrendido) {
      await _programar();
    } else {
      await Workmanager().cancelByUniqueName(_tarea);
    }
  }

  /// ¿Puede la app mostrar notificaciones? null si no se sabe.
  static Future<bool?> permitidas() async {
    if (kIsWeb) return false;
    return _android?.areNotificationsEnabled();
  }

  /// Pide el permiso de notificaciones (Android 13 o superior lo pregunta; en
  /// los anteriores ya está dado). Devuelve false si no se dio.
  static Future<bool> pedirPermiso() async {
    if (kIsWeb) return false;
    return await _android?.requestNotificationsPermission() ?? true;
  }

  /// Al abrir la app por primera vez después de instalar o actualizar: como el
  /// resumen viene prendido, se pide el permiso una sola vez. Si se niega, la
  /// pestaña Avisos lo muestra y explica cómo arreglarlo; no se vuelve a pedir solo.
  static Future<void> pedirPermisoInicial(SharedPreferences prefs) async {
    if (kIsWeb || (prefs.getInt(clavePermisoPedido) ?? 0) >= _versionPermiso) return;
    await prefs.setInt(clavePermisoPedido, _versionPermiso);
    if (PreferenciasAvisos.leer(prefs).algunoPrendido && await permitidas() != true) await pedirPermiso();
  }
}

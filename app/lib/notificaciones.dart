/// Avisos en el teléfono cuando cambia el nivel del río.
///
/// En esta fase son notificaciones locales: la app consulta los datos al abrirse
/// y, si Android lo permite, cada tanto en segundo plano. Android puede demorar
/// esas consultas; los avisos inmediatos llegan con las notificaciones push (Fase 4).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'datos.dart';
import 'modelos.dart';
import 'textos.dart';

const _tarea = 'chequeo_nivel';
const claveActivos = 'avisos_activos';
const claveDesde = 'avisar_desde';
const _claveUltimo = 'ultimo_nivel';
const _claveUrl = 'url_base';
const _claveHorasSinDato = 'horas_sin_dato';

int _orden(Nivel n) => switch (n) {
      Nivel.normal => 0,
      Nivel.atencion => 1,
      Nivel.alerta => 2,
      Nivel.evacuacion => 3,
      Nivel.sinDato => -1,
    };

/// ¿Hay que avisar al pasar de [anterior] a [nuevo]? Se avisa cuando el nivel
/// cambia y el nuevo (o el que se deja atrás) llega al mínimo elegido en Ajustes.
/// Nunca se avisa por "sin dato".
bool debeAvisar(Nivel? anterior, Nivel nuevo, Nivel minimo) {
  if (nuevo == Nivel.sinDato || anterior == nuevo) return false;
  if (anterior == null || anterior == Nivel.sinDato) return _orden(nuevo) >= _orden(minimo);
  return _orden(nuevo) >= _orden(minimo) || _orden(anterior) >= _orden(minimo);
}

/// Título y texto de la notificación.
(String, String) mensajeDeCambio(Nivel? anterior, Actual actual, Nivel nuevo, DateTime ahora) {
  final nombre = estiloNivel(nuevo).nombre.toUpperCase();
  final subio = anterior == null || _orden(nuevo) > _orden(anterior);
  final titulo = subio ? 'Río Uruguay: nivel de $nombre' : 'Río Uruguay: bajó a nivel $nombre';
  final a = actual.altura!;
  return (
    titulo,
    'Altura en Paysandú: ${formatoAltura(a.valorM)} m (${formatoFecha(a.fecha, ahora)}). '
        'Fuente: CARU. La alerta oficial la dan el Sinae y el Cecoed.',
  );
}

final _plugin = FlutterLocalNotificationsPlugin();

Future<void> _iniciarPlugin() => _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

/// Compara el nivel con el último conocido y, si corresponde, muestra el aviso.
Future<void> revisarNivel(Actual? actual, SharedPreferences prefs, {DateTime? ahora}) async {
  if (kIsWeb || actual == null) return;
  ahora ??= DateTime.now();
  final nuevo = actual.nivelVigente(ahora, prefs.getInt(_claveHorasSinDato) ?? 48);
  if (nuevo == Nivel.sinDato) return;
  final guardado = prefs.getString(_claveUltimo);
  final anterior = guardado == null ? null : nivelDesdeTexto(guardado);
  await prefs.setString(_claveUltimo, nivelATexto(nuevo));
  if (prefs.getBool(claveActivos) != true) return;
  final minimo = nivelDesdeTexto(prefs.getString(claveDesde) ?? 'alerta');
  if (!debeAvisar(anterior, nuevo, minimo)) return;
  final (titulo, cuerpo) = mensajeDeCambio(anterior, actual, nuevo, ahora);
  await _plugin.show(
    id: 1,
    title: titulo,
    body: cuerpo,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'nivel_rio',
        'Nivel del río',
        channelDescription: 'Avisos cuando cambia el nivel del río Uruguay en Paysandú',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(cuerpo),
      ),
    ),
  );
}

/// Punto de entrada de la tarea en segundo plano (la llama Android, no la app).
@pragma('vm:entry-point')
void tareaEnSegundoPlano() {
  Workmanager().executeTask((tarea, datosDeEntrada) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(_claveUrl);
      if (url == null) return true;
      await _iniciarPlugin();
      final datos = await Repositorio(url).cargar();
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
    await prefs.setString(_claveUrl, config.urlBase);
    await prefs.setInt(_claveHorasSinDato, config.horasSinDato);
    await _iniciarPlugin();
    await Workmanager().initialize(tareaEnSegundoPlano);
    if (prefs.getBool(claveActivos) == true) await _programar();
  }

  static Future<void> _programar() => Workmanager().registerPeriodicTask(
        _tarea,
        _tarea,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  /// Activa o desactiva los avisos. Devuelve false si el usuario no dio permiso.
  static Future<bool> activar(bool activar, SharedPreferences prefs) async {
    if (kIsWeb) return false;
    if (!activar) {
      await prefs.setBool(claveActivos, false);
      await Workmanager().cancelByUniqueName(_tarea);
      return true;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final permitido = await android?.requestNotificationsPermission() ?? true;
    if (!permitido) return false;
    await prefs.setBool(claveActivos, true);
    await _programar();
    return true;
  }
}

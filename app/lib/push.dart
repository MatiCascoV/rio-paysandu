/// Avisos push por Firebase Cloud Messaging (Fase 4).
///
/// Los mensajes son SOLO DATOS, sin texto: `{"tipo":"urgente",...}` o
/// `{"tipo":"resumen",...}` (ver avisos.dart). Al recibir uno, con la app
/// abierta, en segundo plano o cerrada, el teléfono baja actual.json y arma la
/// notificación con ese dato. Lo que se recibe se decide con temas de FCM: no
/// hay cuentas ni se guarda ningún dato de nadie.
library;

import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'avisos.dart';
import 'datos.dart';
import 'notificaciones.dart';

/// Firma de los temas que quedaron suscritos la última vez que se sincronizó todo bien.
const claveTemasAlDia = 'temas_al_dia';

/// Manejador con la app cerrada o en segundo plano: corre en un isolate aparte,
/// sin la app, así que prepara todo de nuevo.
@pragma('vm:entry-point')
Future<void> manejarPushEnSegundoPlano(RemoteMessage mensaje) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp();
    await atenderPush(mensaje);
  } catch (_) {
    // Si falla, el aviso llega con la revisión local de respaldo.
  }
}

/// Valida el mensaje, baja el dato y muestra lo que corresponda. Del mensaje
/// solo se usan sus datos validados y la hora de envío que pone FCM.
Future<void> atenderPush(RemoteMessage mensaje) async {
  final prefs = await SharedPreferences.getInstance();
  final avisos = await avisosDePush(mensaje.data, prefs, (url) => Repositorio(url).cargar(soloActual: true),
      enviado: mensaje.sentTime);
  if (avisos.isEmpty) return;
  await iniciarPlugin();
  for (final aviso in avisos) {
    await mostrarAviso(aviso);
  }
}

/// Suscribe y desuscribe temas (en la app, FCM; en las pruebas, uno falso).
abstract class Suscriptor {
  Future<void> suscribir(String tema);
  Future<void> desuscribir(String tema);
}

class _SuscriptorFcm implements Suscriptor {
  @override
  Future<void> suscribir(String tema) => FirebaseMessaging.instance.subscribeToTopic(tema);

  @override
  Future<void> desuscribir(String tema) => FirebaseMessaging.instance.unsubscribeFromTopic(tema);
}

/// Deja el teléfono en los temas que piden las preferencias y lo saca de todos
/// los demás. Es idempotente: se puede repetir sin cambiar nada. Devuelve true
/// si todo quedó al día; si algo falló (por ejemplo, sin conexión) devuelve
/// false y se vuelve a intentar la próxima vez que se abra la app. Nunca lanza.
Future<bool> sincronizarTemas(SharedPreferences prefs, Suscriptor suscriptor,
    {bool prueba = temasDePrueba, Duration tiempoMaximo = const Duration(seconds: 20)}) async {
  final deseados = temasDeseados(PreferenciasAvisos.leer(prefs), prueba: prueba);
  final firma = firmaTemas(deseados);
  var ok = true;
  Future<void> uno(String tema) async {
    try {
      await (deseados.contains(tema) ? suscriptor.suscribir(tema) : suscriptor.desuscribir(tema)).timeout(tiempoMaximo);
    } catch (_) {
      ok = false;
    }
  }

  await Future.wait(todosLosTemas.map(uno));
  try {
    if (!ok) {
      await prefs.remove(claveTemasAlDia);
    } else if (firmaTemas(temasDeseados(PreferenciasAvisos.leer(prefs), prueba: prueba)) == firma) {
      // Si las preferencias cambiaron mientras tanto, la sincronización que sigue las toma.
      await prefs.setString(claveTemasAlDia, firma);
    }
  } catch (_) {}
  return ok;
}

/// ¿Los temas suscritos son los que piden las preferencias de ahora?
bool temasAlDia(SharedPreferences prefs, {bool prueba = temasDePrueba}) =>
    prefs.getString(claveTemasAlDia) == firmaTemas(temasDeseados(PreferenciasAvisos.leer(prefs), prueba: prueba));

class Push {
  /// true si Firebase arrancó en este teléfono (sin servicios de Google, no).
  static bool disponible = false;

  /// Las sincronizaciones van de a una: si se tocan dos interruptores seguidos,
  /// la segunda no puede terminar antes que la primera y dejar un tema de más.
  static Future<bool> _cola = Future.value(true);

  /// Se llama una vez al abrir la app (después de Notificaciones.iniciar, que
  /// migra las preferencias). La sincronización de temas no se espera: sin
  /// conexión puede tardar y la app tiene que abrir igual.
  static Future<void> iniciar(SharedPreferences prefs) async {
    if (kIsWeb) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(manejarPushEnSegundoPlano);
    // Con la app abierta, el push llega acá (y se muestra igual: puede no estar a la vista).
    FirebaseMessaging.onMessage.listen((m) => unawaited(atenderPush(m).catchError((_) {})));
    disponible = true;
    unawaited(sincronizar(prefs));
  }

  /// Sincroniza los temas con las preferencias. Sin Firebase devuelve false.
  static Future<bool> sincronizar(SharedPreferences prefs) {
    if (!disponible) return Future.value(false);
    final resultado = _cola.then((_) => sincronizarTemas(prefs, _SuscriptorFcm()));
    _cola = resultado;
    return resultado;
  }
}

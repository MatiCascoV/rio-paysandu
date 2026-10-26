/// Reglas de los avisos (Fase 4): cuándo sale el aviso urgente y cuándo el
/// resumen del día, qué dicen, a qué temas de FCM se suscribe el teléfono y
/// cómo se valida un mensaje push.
///
/// Es la misma regla que `lector/avisos.py` (el servidor). La usan las tres
/// puertas por donde la app se entera del río: la app abierta, el push y la
/// revisión local de respaldo (workmanager). Las tres comparten en
/// SharedPreferences la marca de lo ya avisado (último nivel visto y día del
/// último resumen), así un mismo aviso nunca sale dos veces.
///
/// Sin plugins: todo se prueba sin teléfono.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'datos.dart';
import 'modelos.dart';
import 'textos.dart';

/// Ciudad de los temas y de los mensajes push (Fase 4.b: más ciudades).
const ciudad = 'paysandu';

// ---------- preferencias ----------

const claveUrgente = 'aviso_urgente';
const claveUrgenteDesde = 'aviso_urgente_desde';
const claveResumen = 'aviso_resumen';
const claveVersionAvisos = 'avisos_version';

/// De la versión con solo avisos locales. Se migran una vez (ver [migrarPreferencias]).
const claveViejaActivos = 'avisos_activos';
const claveViejaDesde = 'avisar_desde';

/// Las comparten la app, el push y la tarea en segundo plano (cada uno en su isolate).
const claveUrl = 'url_base';
const claveHorasSinDato = 'horas_sin_dato';
const claveUltimoNivel = 'ultimo_nivel';
const claveUltimoResumen = 'ultimo_resumen_dia';

/// `generado` de la última publicación con dato que vio este teléfono.
const claveUltimoGenerado = 'ultimo_nivel_generado';

/// Lo que eligió la persona en la pestaña Avisos.
class PreferenciasAvisos {
  /// Aviso urgente: apagado en una instalación nueva.
  final bool urgente;

  /// Desde qué nivel avisa el urgente: [Nivel.alerta] ("Desde alerta") o
  /// [Nivel.evacuacion] ("Solo evacuación").
  final Nivel desde;

  /// Resumen del día: prendido por defecto.
  final bool resumen;

  const PreferenciasAvisos({this.urgente = false, this.desde = Nivel.alerta, this.resumen = true});

  bool get algunoPrendido => urgente || resumen;

  /// Lee las preferencias. Si todavía no se migraron, interpreta las viejas
  /// igual que la migración, sin escribir nada (la pantalla puede leer antes).
  factory PreferenciasAvisos.leer(SharedPreferences prefs) => PreferenciasAvisos(
        urgente: prefs.getBool(claveUrgente) ?? prefs.getBool(claveViejaActivos) ?? false,
        desde: _desdeDeTexto(prefs.getString(claveUrgenteDesde) ?? prefs.getString(claveViejaDesde)),
        resumen: prefs.getBool(claveResumen) ?? true,
      );
}

/// "evacuacion" es "Solo evacuación"; cualquier otra cosa (también "atencion"
/// de la versión vieja, que ya no existe) es "Desde alerta".
Nivel _desdeDeTexto(String? texto) => texto == 'evacuacion' ? Nivel.evacuacion : Nivel.alerta;

/// Pasa las preferencias de la versión vieja a las nuevas, una sola vez:
/// quien tenía los avisos prendidos queda con el urgente prendido; desde
/// atención o alerta pasa a "Desde alerta"; desde evacuación, a "Solo
/// evacuación". El resumen queda prendido para todos. No hace reload: lo hace
/// quien la llama. Se puede llamar desde cualquier isolate y las veces que sea.
Future<void> migrarPreferencias(SharedPreferences prefs) async {
  if ((prefs.getInt(claveVersionAvisos) ?? 0) >= 1) return;
  final p = PreferenciasAvisos.leer(prefs);
  await prefs.setBool(claveUrgente, p.urgente);
  await prefs.setString(claveUrgenteDesde, nivelATexto(p.desde));
  await prefs.setBool(claveResumen, p.resumen);
  await prefs.remove(claveViejaActivos);
  await prefs.remove(claveViejaDesde);
  await prefs.setInt(claveVersionAvisos, 1);
}

// ---------- reglas (las de lector/avisos.py) ----------

int ordenNivel(Nivel n) => switch (n) {
      Nivel.normal => 0,
      Nivel.atencion => 1,
      Nivel.alerta => 2,
      Nivel.evacuacion => 3,
      Nivel.sinDato => -1,
    };

/// ¿Sale el aviso urgente al pasar de [anterior] (el último nivel CON DATO que
/// vio este teléfono) a [nuevo]? Solo al SUBIR a alerta o a evacuación, y si
/// llega al mínimo elegido ([desde]). Nada por bajadas, por normal → atención
/// ni por "sin dato". Sin nivel anterior no se avisa (como el servidor).
bool subidaUrgente(Nivel? anterior, Nivel nuevo, Nivel desde) =>
    (nuevo == Nivel.alerta || nuevo == Nivel.evacuacion) &&
    anterior != null &&
    anterior != Nivel.sinDato &&
    ordenNivel(nuevo) > ordenNivel(anterior) &&
    ordenNivel(nuevo) >= ordenNivel(desde);

enum FuenteResumen { prefectura, estacion }

/// Si a esta hora (de Uruguay) todavía no llegó la lectura de Prefectura del
/// día, el resumen sale con la estación automática.
const horaRespaldoResumen = 10;

String _dos(int n) => n.toString().padLeft(2, '0');

/// Día en hora de Uruguay (UTC-3 fijo, sin horario de verano): "2026-10-09".
String diaUruguay(DateTime fecha) {
  final f = enHoraUruguay(fecha);
  return '${f.year}-${_dos(f.month)}-${_dos(f.day)}';
}

/// Con qué fuente saldría el resumen del día con este dato, sin mirar si ya
/// salió (igual que `resumen_listo` de avisos.py): Prefectura si ya llegó su
/// lectura de hoy; la estación si no llegó pero ya son las 10; null si no
/// corresponde (nivel normal o sin dato, sin fecha, o antes de las 10 sin Prefectura).
FuenteResumen? resumenListo(Actual actual, Nivel nivel) {
  if (ordenNivel(nivel) < ordenNivel(Nivel.atencion)) return null;
  final generado = actual.generado;
  if (generado == null) return null;
  final prefectura = actual.prefectura;
  if (prefectura != null && diaUruguay(prefectura.fecha) == diaUruguay(generado)) return FuenteResumen.prefectura;
  if (enHoraUruguay(generado).hour >= horaRespaldoResumen) return FuenteResumen.estacion;
  return null;
}

// ---------- textos de las notificaciones ----------

enum TipoAviso { urgente, resumen }

/// Una notificación a mostrar. El texto sale siempre de actual.json, nunca del push.
class Aviso {
  final TipoAviso tipo;
  final String titulo;
  final String texto;

  const Aviso(this.tipo, this.titulo, this.texto);

  @override
  String toString() => '$tipo: $titulo / $texto';
}

const _oficial = 'La alerta oficial la dan el Sinae y el Cecoed.';

String _aVerificar(Actual a) => a.avisos.contains('dato_a_verificar') ? 'Dato a verificar por CARU. ' : '';

/// "9/10 a las 12:00". Fecha completa: la notificación puede leerse al día
/// siguiente y "hoy" sería falso.
String _cuando(DateTime fecha) {
  final f = enHoraUruguay(fecha);
  return '${f.day}/${f.month} a las ${_dos(f.hour)}:${_dos(f.minute)}';
}

/// "Río Uruguay: subió a ALERTA". [nivel] es el vigente, que tiene altura.
Aviso avisoUrgente(Actual actual, Nivel nivel) {
  final a = actual.altura!;
  return Aviso(
    TipoAviso.urgente,
    'Río Uruguay: subió a ${estiloNivel(nivel).nombre.toUpperCase()}',
    'Altura en Paysandú: ${formatoAltura(a.valorM)} m (el ${_cuando(a.fecha)}). ${_aVerificar(actual)}'
        'Fuente: CARU. $_oficial',
  );
}

/// Si llega un push urgente y el dato no se pudo bajar, o todavía no muestra la
/// subida, se avisa igual pero sin inventar nada: ni nivel ni altura. Callar
/// durante una crecida es peor. Cuando se consigue el dato, el aviso de verdad
/// reemplaza a este (usan la misma notificación).
const avisoUrgenteSinDato = Aviso(
  TipoAviso.urgente,
  'Río Uruguay: hay novedades',
  'Todavía no se pudo ver el dato nuevo. Abrí la app para ver el nivel. $_oficial',
);

/// "Bajó 13 cm en 24 h. " con la lectura de Prefectura, o nada si no trae la
/// variación de 24 horas.
String _variacion24(Lectura p) {
  final periodo = (p.periodo ?? '').replaceAll(' ', '').toLowerCase();
  final v = p.variacionM;
  if (v == null || (periodo != '24hs' && periodo != '24h')) return '';
  if ((v.abs() * 100).round() == 0 || p.estado == 'estacionado') return 'Sin cambios en 24 h. ';
  final sube = switch (p.estado) { 'crece' => true, 'baja' => false, _ => v > 0 };
  return '${sube ? 'Subió' : 'Bajó'} ${formatoDiferencia(v)} en 24 h. ';
}

/// "Río hoy: 5,85 m · Alerta" / "Bajó 13 cm en 24 h. Abrí la app…".
/// Con Prefectura va su lectura de la mañana y su variación de 24 h; con la
/// estación se dice la fuente y no se inventa una variación de 24 h.
Aviso avisoResumen(Actual actual, Nivel nivel, FuenteResumen fuente) {
  const cierre = 'Abrí la app para ver el dato en tiempo real.';
  final nombre = estiloNivel(nivel).nombre;
  if (fuente == FuenteResumen.prefectura) {
    final p = actual.prefectura!;
    return Aviso(TipoAviso.resumen, 'Río hoy: ${formatoAltura(p.valorM)} m · $nombre',
        '${_variacion24(p)}${_aVerificar(actual)}$cierre');
  }
  final a = actual.altura!;
  final f = enHoraUruguay(a.fecha);
  return Aviso(
    TipoAviso.resumen,
    'Río hoy: ${formatoAltura(a.valorM)} m · $nombre',
    'Dato de la estación automática de CARU de las ${_dos(f.hour)}:${_dos(f.minute)} '
        '(todavía no llegó la lectura de Prefectura). ${_aVerificar(actual)}$cierre',
  );
}

// ---------- decisión compartida ----------

/// Quién revisa el nivel. [Origen.app]: la app abierta y a la vista.
enum Origen { app, respaldo, push }

/// Decide qué avisos mostrar con este [actual] y deja las marcas compartidas.
/// La llaman la app, el push y la revisión de respaldo, en isolates distintos:
/// por eso relee las preferencias, y escribe las marcas ANTES de devolver los
/// avisos (el que llega segundo ya ve la marca).
///
/// - Urgente: [subidaUrgente] contra el último nivel con dato que vio el
///   teléfono, por cualquiera de las tres puertas. Un push urgente
///   ([subidaInformada], enviado a la hora [enviado]) dice que el servidor vio
///   la subida: si este teléfono todavía no tiene nivel anterior, se le cree; y
///   si lo último que vio es de bastante antes del envío ([margenEnvio]) y ya
///   estaba en ese nivel o más, hubo una bajada en el medio que el teléfono no
///   vio (estaba sin revisar): también se le cree. Si el teléfono ya vio la
///   publicación de la subida, no se repite.
/// - Resumen: uno por día de Uruguay, con [resumenListo]. Con la app a la vista
///   el dato ya se está viendo: se marca el día sin notificar. Si en la misma
///   pasada sale un urgente, se marca el día y queda solo el urgente (ya trae
///   la altura; dos notificaciones juntas sobran).
Future<List<Aviso>> decidirAvisos(Actual actual, SharedPreferences prefs, DateTime ahora,
    {Origen origen = Origen.respaldo, Nivel? subidaInformada, DateTime? enviado}) async {
  // Dentro de un mismo isolate (la app abierta y un push en primer plano) las
  // decisiones van de a una: si no, las dos leerían la marca vieja y avisarían
  // las dos. Entre isolates distintos queda una ventana de milisegundos; en el
  // peor caso, la notificación repetida reemplaza a la primera (mismo número).
  while (_decidiendo) {
    final turno = Completer<void>();
    _enEspera.add(turno);
    await turno.future;
  }
  _decidiendo = true;
  try {
    return await _decidir(actual, prefs, ahora, origen, subidaInformada, enviado);
  } finally {
    _decidiendo = false;
    if (_enEspera.isNotEmpty) _enEspera.removeAt(0).complete();
  }
}

bool _decidiendo = false;
final _enEspera = <Completer<void>>[];

/// Para las pruebas: cada prueba de pantallas corre con su propio reloj falso,
/// y una revisión que quedó a medias en la anterior nunca termina.
@visibleForTesting
void reiniciarTurnoDeAvisos() {
  _decidiendo = false;
  _enEspera.clear();
}

/// Tiempo máximo entre que el lector arma una publicación y avisos.yml manda el
/// push (en la práctica, unos pocos minutos).
const margenEnvio = Duration(minutes: 20);

Future<List<Aviso>> _decidir(Actual actual, SharedPreferences prefs, DateTime ahora, Origen origen,
    Nivel? subidaInformada, DateTime? enviado) async {
  await prefs.reload();
  await migrarPreferencias(prefs);
  final p = PreferenciasAvisos.leer(prefs);
  // El nivel lo calcula el lector (con su margen al bajar); acá solo se descarta un dato viejo.
  final nivel = actual.nivelVigente(ahora, prefs.getInt(claveHorasSinDato) ?? 48);
  if (nivel == Nivel.sinDato) return const []; // "sin dato" ni avisa ni se recuerda
  final guardado = prefs.getString(claveUltimoNivel);
  var anterior = guardado == null ? null : nivelDesdeTexto(guardado);
  if (anterior == Nivel.sinDato) anterior = null;
  if (subidaInformada != null) {
    final visto = DateTime.tryParse(prefs.getString(claveUltimoGenerado) ?? '');
    if (anterior == null) {
      anterior = Nivel.normal;
    } else if (ordenNivel(anterior) >= ordenNivel(subidaInformada) &&
        enviado != null &&
        visto != null &&
        visto.isBefore(enviado.subtract(margenEnvio))) {
      anterior = subidaInformada == Nivel.evacuacion ? Nivel.alerta : Nivel.atencion;
    }
  }
  // Esta marca es la que deduplica: un segundo push del mismo urgente ve el nivel ya
  // guardado y no avisa. Es requisito del envío en dos mensajes de avisos.yml (un
  // teléfono que quedó en los dos temas urgentes recibe los dos). Lo prueba "el mismo
  // urgente por dos temas (dos pushes iguales) avisa una sola vez" en avisos_test.dart.
  await prefs.setString(claveUltimoNivel, nivelATexto(nivel));
  final generado = actual.generado;
  if (generado != null) await prefs.setString(claveUltimoGenerado, generado.toUtc().toIso8601String());

  final avisos = <Aviso>[];
  if (p.urgente && subidaUrgente(anterior, nivel, p.desde)) avisos.add(avisoUrgente(actual, nivel));

  final fuente = resumenListo(actual, nivel);
  if (p.resumen && fuente != null) {
    final dia = diaUruguay(actual.generado!);
    // Solo el resumen de hoy: "Río hoy" con el dato de ayer sería falso.
    if (dia == diaUruguay(ahora) && prefs.getString(claveUltimoResumen) != dia) {
      await prefs.setString(claveUltimoResumen, dia);
      if (origen != Origen.app && avisos.isEmpty) avisos.add(avisoResumen(actual, nivel, fuente));
    }
  }
  return avisos;
}

// ---------- push ----------

/// Mensaje push ya validado. Solo dice qué revisar: el texto nunca sale de acá.
class MensajePush {
  final TipoAviso tipo;

  /// Nivel al que subió (solo en el urgente): alerta o evacuación.
  final Nivel? nivel;

  const MensajePush(this.tipo, [this.nivel]);
}

/// Valida los datos de un push: `{"tipo":"urgente","nivel":"alerta"|"evacuacion","ciudad":"paysandu"}`
/// o `{"tipo":"resumen","fuente":"prefectura"|"estacion","ciudad":"paysandu"}`.
/// Lo que no sea exactamente eso se ignora (devuelve null).
MensajePush? validarMensajePush(Map<String, Object?> datos) {
  if (datos['ciudad'] != ciudad) return null;
  switch (datos['tipo']) {
    case 'urgente':
      return switch (datos['nivel']) {
        'alerta' => const MensajePush(TipoAviso.urgente, Nivel.alerta),
        'evacuacion' => const MensajePush(TipoAviso.urgente, Nivel.evacuacion),
        _ => null,
      };
    case 'resumen':
      final fuente = datos['fuente'];
      return fuente == 'prefectura' || fuente == 'estacion' ? const MensajePush(TipoAviso.resumen) : null;
    default:
      return null;
  }
}

/// Cómo baja el push el dato (en la app: `Repositorio(url).cargar(soloActual: true)`).
typedef BajarDatos = Future<Datos> Function(String urlBase);

/// Cómo se muestra un aviso (en la app, `mostrarAviso` de notificaciones.dart).
typedef MostrarAviso = Future<void> Function(Aviso aviso);

/// Con la app cerrada, Android le da al manejador del push unos 20 segundos y
/// después puede cortarlo. Todo tiene que entrar en ~15 s en el peor caso: una
/// descarga de hasta [tiempoDescargaPush], si hace falta una espera de
/// [esperaPush] (el push puede salir antes de que GitHub Pages publique el
/// archivo nuevo) y un solo reintento. Lo que no entre lo cubre el respaldo local.
const tiempoDescargaPush = Duration(seconds: 6);
const esperaPush = Duration(seconds: 3);

/// ¿El dato bajado todavía no muestra lo que anunció el push? Si se armó
/// después del envío ([enviado], la hora de FCM), no: el río cambió después
/// (por ejemplo, un push viejo que llega al prender el teléfono).
bool _atrasado(MensajePush m, Actual a, DateTime? enviado) {
  final generado = a.generado;
  if (enviado != null && generado != null && generado.isAfter(enviado)) return false;
  return m.tipo == TipoAviso.urgente ? ordenNivel(a.nivel) < ordenNivel(m.nivel!) : resumenListo(a, a.nivel) == null;
}

/// Atiende un push (en primer plano, en segundo plano o con la app cerrada).
/// Valida el mensaje, mira las preferencias de este teléfono, baja actual.json
/// y decide con [decidirAvisos], igual que el respaldo, mostrando con [mostrar].
///
/// Para un urgente, si la primera descarga falla o todavía no muestra la
/// subida, se muestra YA [avisoUrgenteSinDato] (Android puede cortar el
/// manejador en cualquier momento) y recién después se reintenta una vez: si
/// aparece el dato, el aviso de verdad reemplaza al genérico (misma
/// notificación). El genérico no cuenta como visto. Para el resumen, sin
/// genérico: un intento y como mucho un reintento corto.
/// [enviado] es la hora de envío que pone FCM (no es texto del mensaje); sin
/// ella se decide igual, solo con el nivel.
Future<void> atenderMensajePush(Map<String, Object?> datos, SharedPreferences prefs, BajarDatos bajar,
    MostrarAviso mostrar,
    {DateTime? enviado, DateTime Function() reloj = DateTime.now, Duration espera = esperaPush}) async {
  final mensaje = validarMensajePush(datos);
  if (mensaje == null) return;
  await prefs.reload();
  await migrarPreferencias(prefs);
  final p = PreferenciasAvisos.leer(prefs);
  final urgente = mensaje.tipo == TipoAviso.urgente;
  // Un push de algo que este teléfono no pidió (por ejemplo, mientras se
  // termina de desuscribir) no hace nada, ni siquiera bajar el dato.
  if (urgente ? !(p.urgente && ordenNivel(mensaje.nivel!) >= ordenNivel(p.desde)) : !p.resumen) return;

  final url = prefs.getString(claveUrl);
  Future<Actual?> bajarUna() async {
    if (url == null) return null;
    try {
      final d = await bajar(url).timeout(tiempoDescargaPush);
      return d.sinConexion ? null : d.actual; // la copia guardada es vieja: no sirve para avisar
    } catch (_) {
      return null;
    }
  }

  var actual = await bajarUna();
  if (actual == null || _atrasado(mensaje, actual, enviado)) {
    if (urgente) await mostrar(avisoUrgenteSinDato);
    await Future<void>.delayed(espera);
    actual = await bajarUna() ?? actual;
  }
  if (actual == null) return;
  for (final aviso in await decidirAvisos(actual, prefs, reloj(),
      origen: Origen.push, subidaInformada: urgente ? mensaje.nivel : null, enviado: enviado)) {
    await mostrar(aviso);
  }
}

// ---------- temas de FCM ----------

/// Con `--dart-define=TEMAS_PRUEBA=true` los temas llevan el prefijo `prueba-`,
/// los mismos que usa avisos.yml con la entrada `prueba`.
const temasDePrueba = bool.fromEnvironment('TEMAS_PRUEBA');

String _tema(String tipo, bool prueba) => '${prueba ? 'prueba-' : ''}$tipo-$ciudad';

/// "Desde alerta" → alerta-paysandu; "Solo evacuación" → evacuacion-paysandu;
/// resumen → resumen-paysandu. Un solo tema urgente por teléfono: avisos.yml
/// manda el urgente de evacuación en dos mensajes (uno a cada tema urgente) y
/// así le llega uno solo. Si quedara en los dos (sincronización a medias), le
/// llegan dos pushes, pero la app no repite el aviso (claveUltimoNivel, en _decidir).
Set<String> temasDeseados(PreferenciasAvisos p, {bool prueba = temasDePrueba}) => {
      if (p.urgente) _tema(p.desde == Nivel.evacuacion ? 'evacuacion' : 'alerta', prueba),
      if (p.resumen) _tema('resumen', prueba),
    };

/// Todos los temas que pudo usar la app, reales y de prueba: al sincronizar se
/// sale de los que no corresponden (también si antes se instaló la otra versión).
final Set<String> todosLosTemas = {
  for (final prueba in [false, true])
    for (final tipo in ['alerta', 'evacuacion', 'resumen']) _tema(tipo, prueba),
};

/// Texto que identifica un conjunto de temas, para saber si ya quedó sincronizado.
String firmaTemas(Set<String> temas) => (temas.toList()..sort()).join(',');

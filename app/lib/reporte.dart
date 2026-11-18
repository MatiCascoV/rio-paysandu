import 'avisos.dart';
import 'modelos.dart';
import 'textos.dart';

/// Correo al que llegan los reportes. Lo recibe y conserva el responsable de la app.
const correoReportes = 'mcasco.paysandu@gmail.com';

/// Dónde se avisa por GitHub (hace falta cuenta; el reporte es público).
final Uri urlReporteGitHub = Uri.parse('https://github.com/MatiCascoV/rio-paysandu/issues/new');

/// Lo único que va en los "Datos técnicos" del reporte. No hay nada más: ni
/// identificadores de instalación, ni ubicación, ni modelo del teléfono, ni red.
class DatosReporte {
  final String version;
  final String build;

  /// Texto de Platform.operatingSystemVersion.
  final String androidVersion;

  /// Fecha y hora del teléfono al armar el reporte.
  final DateTime ahora;

  /// Última lectura de altura mostrada, o null si no había.
  final Lectura? ultimaLectura;

  /// null si no había lectura; true si la app la mostraba como desactualizada.
  final bool? desactualizado;

  final bool avisoUrgente;
  final bool resumenDelDia;

  const DatosReporte({
    required this.version,
    required this.build,
    required this.androidVersion,
    required this.ahora,
    this.ultimaLectura,
    this.desactualizado,
    required this.avisoUrgente,
    required this.resumenDelDia,
  });

  /// Arma los datos del reporte a partir de lo que la app tiene en pantalla.
  factory DatosReporte.desde({
    required String version,
    required String build,
    required String androidVersion,
    required DateTime ahora,
    Actual? actual,
    int horasSinDato = 48,
    required PreferenciasAvisos avisos,
  }) {
    final lectura = actual?.altura;
    return DatosReporte(
      version: version,
      build: build,
      androidVersion: androidVersion,
      ahora: ahora,
      ultimaLectura: lectura,
      desactualizado: lectura == null ? null : actual!.nivelVigente(ahora, horasSinDato) == Nivel.sinDato,
      avisoUrgente: avisos.urgente,
      resumenDelDia: avisos.resumen,
    );
  }
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// "2026-11-06 14:05 (UTC-03:00)", en la hora del teléfono.
String fechaConZona(DateTime fecha) {
  final f = fecha.toLocal();
  final d = f.timeZoneOffset;
  final minutos = d.inMinutes.abs();
  final zona = 'UTC${d.isNegative ? '-' : '+'}${_dos(minutos ~/ 60)}:${_dos(minutos % 60)}';
  return '${f.year}-${_dos(f.month)}-${_dos(f.day)} ${_dos(f.hour)}:${_dos(f.minute)} ($zona)';
}

String _siNo(bool v) => v ? 'sí' : 'no';

/// Asunto del correo.
String asuntoReporte(String version) => 'Mi Río UY: problema con la app (v$version)';

/// Cuerpo del correo (texto plano). Primero lo que escribe la persona, después los datos técnicos.
String cuerpoReporte(DatosReporte d) {
  final l = d.ultimaLectura;
  final ultimo = l == null
      ? 'sin dato'
      : '${fechaConZona(l.fecha)}, ${formatoAltura(l.valorM)} m'
          '${d.desactualizado == true ? ' (marcado como desactualizado)' : ' (no marcado como desactualizado)'}';
  return 'Contanos qué pasó (¿el dato está viejo, no coincide con CARU, falló algo?):\r\n'
      '\r\n\r\n\r\n'
      '----\r\n'
      'Datos técnicos (podés borrarlos):\r\n'
      'App: ${d.version} (build ${d.build})\r\n'
      'Android: ${d.androidVersion}\r\n'
      'Fecha y hora del teléfono: ${fechaConZona(d.ahora)}\r\n'
      'Último dato mostrado: $ultimo\r\n'
      'Avisos: urgente ${_siNo(d.avisoUrgente)}, resumen ${_siNo(d.resumenDelDia)}\r\n';
}

/// mailto armado a mano: `Uri(queryParameters:)` codifica el espacio como "+",
/// y en un mailto eso se ve como un "+" de verdad.
Uri armarMailto(DatosReporte d) {
  final asunto = Uri.encodeComponent(asuntoReporte(d.version));
  final cuerpo = Uri.encodeComponent(cuerpoReporte(d));
  return Uri.parse('mailto:$correoReportes?subject=$asunto&body=$cuerpo');
}

/// Textos y formatos que ve el vecino. Todo en español rioplatense, sin tecnicismos.
library;

import 'package:flutter/material.dart';

import 'modelos.dart';

/// Las horas se muestran siempre en hora de Uruguay (UTC-3), esté donde esté el teléfono.
DateTime enHoraUruguay(DateTime fecha) => fecha.toUtc().subtract(const Duration(hours: 3));

String _dos(int n) => n.toString().padLeft(2, '0');

/// 5.9 -> "5,90"
String formatoAltura(double metros) => metros.toStringAsFixed(2).replaceAll('.', ',');

/// "hoy 12:00", "ayer 06:00" o "7/10 06:00".
String formatoFecha(DateTime fecha, DateTime ahora) {
  final f = enHoraUruguay(fecha);
  final a = enHoraUruguay(ahora);
  final dias = DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(f.year, f.month, f.day)).inDays;
  final hora = '${_dos(f.hour)}:${_dos(f.minute)}';
  if (dias == 0) return 'hoy $hora';
  if (dias == 1) return 'ayer $hora';
  // Un dato guardado de hace casi un año necesita el año para no confundirse.
  if (dias > 300) return '${f.day}/${f.month}/${f.year} $hora';
  return '${f.day}/${f.month} $hora';
}

/// "8/10/2026"
String formatoDia(DateTime fecha) => '${fecha.day}/${fecha.month}/${fecha.year}';

/// "7/10" para los ejes del gráfico.
String formatoDiaCorto(DateTime fecha) {
  final f = enHoraUruguay(fecha);
  return '${f.day}/${f.month}';
}

String formatoMiles(int n) {
  final s = n.toString();
  final partes = <String>[];
  for (var i = s.length; i > 0; i -= 3) {
    partes.insert(0, s.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  return partes.join('.');
}

String _centimetros(double metros) {
  final cm = (metros.abs() * 100).round();
  return cm == 1 ? '1 cm' : '$cm cm';
}

/// Diferencia entre dos alturas: "94 cm" o "1,19 m".
String formatoDiferencia(double metros) =>
    metros.abs() < 1 ? _centimetros(metros) : '${formatoAltura(metros.abs())} m';

/// "Crece 30 cm en 24 h", "Baja 5 cm en 30 min" o "Estable".
/// Con [pasado] (cuando el dato ya es viejo): "Crecía…", "Bajaba…".
String textoTendencia(Lectura l, {bool pasado = false}) {
  final periodo = (l.periodo ?? '').replaceAll('hs', 'h');
  final variacion = l.variacionM;
  final sinCambio = variacion == null || (variacion.abs() * 100).round() == 0;
  final enPeriodo = periodo.isEmpty ? '' : ' en $periodo';
  switch (l.estado) {
    case 'crece':
      final verbo = pasado ? 'Crecía' : 'Crece';
      return sinCambio ? verbo : '$verbo ${_centimetros(variacion)}$enPeriodo';
    case 'baja':
      final verbo = pasado ? 'Bajaba' : 'Baja';
      return sinCambio ? verbo : '$verbo ${_centimetros(variacion)}$enPeriodo';
    case 'estacionado':
      final verbo = pasado ? 'Estaba estable' : 'Estable';
      return periodo.isEmpty ? verbo : '$verbo (sin cambios$enPeriodo)';
    default:
      return 'No se sabe si crece o baja';
  }
}

IconData iconoTendencia(Lectura l) => switch (l.estado) {
      'crece' => Icons.arrow_upward,
      'baja' => Icons.arrow_downward,
      'estacionado' => Icons.arrow_forward,
      _ => Icons.help_outline,
    };

/// Color de fondo, color del texto, ícono y nombre de cada nivel. Los pares de
/// colores tienen contraste alto (6,5:1 o más) y el nivel siempre se dice con texto.
class EstiloNivel {
  final String nombre;
  final Color fondo;
  final Color texto;
  final IconData icono;
  const EstiloNivel(this.nombre, this.fondo, this.texto, this.icono);
}

EstiloNivel estiloNivel(Nivel n) => switch (n) {
      Nivel.normal => const EstiloNivel('Normal', Color(0xFF1B5E20), Colors.white, Icons.check_circle),
      Nivel.atencion => const EstiloNivel('Atención', Color(0xFFFFD600), Colors.black, Icons.visibility),
      Nivel.alerta => const EstiloNivel('Alerta', Color(0xFFFF9800), Colors.black, Icons.warning),
      Nivel.evacuacion => const EstiloNivel('Evacuación', Color(0xFFB71C1C), Colors.white, Icons.report),
      Nivel.sinDato => const EstiloNivel('Sin dato', Color(0xFF424242), Colors.white, Icons.help),
    };

/// Frase que acompaña al nivel. Si se conoce la altura, dice cuánto falta para
/// el nivel siguiente: es una resta entre valores publicados, no una estimación.
String descripcionNivel(Nivel n, Umbrales? u, [double? alturaM]) {
  String ref(double? m) => m == null ? '' : ' (${formatoAltura(m)} m)';
  String falta(double? umbral, String nombre) => umbral == null || alturaM == null || umbral <= alturaM
      ? ''
      : ' Faltan ${formatoDiferencia(umbral - alturaM)} para el nivel de $nombre${ref(umbral)}.';
  switch (n) {
    case Nivel.normal:
      return u?.atencionM != null
          ? 'El río está por debajo del nivel de atención.${falta(u!.atencionM, 'atención')}'
          : 'El río está por debajo del nivel de alerta.${falta(u?.alertaM, 'alerta')}';
    case Nivel.atencion:
      return 'El río pasó el nivel de atención${ref(u?.atencionM)}.${falta(u?.alertaM, 'alerta')}';
    case Nivel.alerta:
      return 'El río pasó el nivel de alerta${ref(u?.alertaM)}.${falta(u?.evacuacionM, 'evacuación')}';
    case Nivel.evacuacion:
      return 'El río pasó el nivel de evacuación${ref(u?.evacuacionM)}. Si vivís cerca del río, prepará la '
          'salida. La orden de evacuar la da el Cecoed. Si hay personas en peligro, llamá al 911.';
    case Nivel.sinDato:
      return 'No hay un dato reciente del nivel del río. Esto no quiere decir que el río esté bajo.';
  }
}

/// Explicación de cada aviso que manda el lector. Los que no conocemos no se muestran.
String? textoAviso(String codigo) => switch (codigo) {
      'dato_desactualizado' => 'Este dato puede estar desactualizado. Fijate en la fecha y la hora.',
      'estacion_desactualizada' =>
        'La estación automática no está informando. Se muestra la lectura de Prefectura.',
      'dato_a_verificar' => 'Este dato puede tener un error. Puede cambiar cuando CARU lo revise.',
      'dato_fuera_de_rango' => 'Llegó un dato con error y no se muestra.',
      'fuente_no_disponible' => 'No llegó información nueva de CARU. Se muestra el último dato que hay.',
      _ => null,
    };

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

/// "Crece 30 cm en 24 h", "Baja 5 cm en 30 min" o "Estable".
String textoTendencia(Lectura l) {
  final periodo = (l.periodo ?? '').replaceAll('hs', 'h');
  final variacion = l.variacionM;
  final sinCambio = variacion == null || (variacion.abs() * 100).round() == 0;
  final enPeriodo = periodo.isEmpty ? '' : ' en $periodo';
  switch (l.estado) {
    case 'crece':
      return sinCambio ? 'Crece' : 'Crece ${_centimetros(variacion)}$enPeriodo';
    case 'baja':
      return sinCambio ? 'Baja' : 'Baja ${_centimetros(variacion)}$enPeriodo';
    case 'estacionado':
      return periodo.isEmpty ? 'Estable' : 'Estable (sin cambios$enPeriodo)';
    default:
      return 'Sin información de tendencia';
  }
}

IconData iconoTendencia(Lectura l) => switch (l.estado) {
      'crece' => Icons.arrow_upward,
      'baja' => Icons.arrow_downward,
      'estacionado' => Icons.arrow_forward,
      _ => Icons.help_outline,
    };

/// Color de fondo, color del texto, ícono y nombre de cada nivel. Los pares de
/// colores tienen contraste alto (más de 7:1) y el nivel siempre se dice con texto.
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

String descripcionNivel(Nivel n, Umbrales? u) {
  String ref(double? m) => m == null ? '' : ' (${formatoAltura(m)} m)';
  return switch (n) {
    Nivel.normal => 'El río está por debajo de los niveles de aviso.',
    Nivel.atencion => 'El río superó el nivel de atención${ref(u?.atencionM)}. Seguí la información.',
    Nivel.alerta => 'El río superó el nivel de alerta${ref(u?.alertaM)}. Estate atento a los avisos oficiales.',
    Nivel.evacuacion =>
      'El río superó el nivel de evacuación${ref(u?.evacuacionM)}. Seguí las indicaciones del Cecoed.',
    Nivel.sinDato => 'No hay un dato reciente y confiable del nivel del río.',
  };
}

/// Explicación de cada aviso que manda el lector. Los que no conocemos no se muestran.
String? textoAviso(String codigo) => switch (codigo) {
      'dato_desactualizado' => 'Este dato puede estar desactualizado. Fijate en la fecha y la hora.',
      'estacion_desactualizada' =>
        'La estación automática no está informando. Se muestra la lectura de Prefectura.',
      'dato_a_verificar' =>
        'La fuente informó un cambio brusco o datos que no coinciden. Este valor puede corregirse.',
      'dato_fuera_de_rango' => 'Se descartó una lectura con error de la fuente.',
      'fuente_no_disponible' => 'No se pudo consultar a CARU. Se muestra el último dato disponible.',
      _ => null,
    };

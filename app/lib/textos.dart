/// Textos y formatos que ve el vecino. Todo en español rioplatense, sin tecnicismos.
library;

import 'package:flutter/material.dart';

import 'modelos.dart';
import 'tema.dart';

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

/// Colores, ícono y nombre de cada nivel. El nivel siempre se dice con ícono y
/// palabra, nunca solo con color. Contraste del texto sobre el relleno: 5:1 o más.
class EstiloNivel {
  final String nombre;
  final Color _fondoClaro;
  final Color _fondoOscuro;
  final Color texto;
  final Color _trazoClaro;
  final Color _trazoOscuro;
  final IconData icono;
  const EstiloNivel(this.nombre, this._fondoClaro, this._fondoOscuro, this.texto, this._trazoClaro,
      this._trazoOscuro, this.icono);

  /// Relleno de la franja de nivel.
  Color get fondo => Colores.oscuro ? _fondoOscuro : _fondoClaro;

  /// Color del nivel para trazos sobre el fondo de la app: marcas de la escalera
  /// y líneas del gráfico. Tono oscuro en modo claro y claro en modo oscuro.
  Color get oscuro => Colores.oscuro ? _trazoOscuro : _trazoClaro;
}

const _tinta = Color(0xFF111B24);

EstiloNivel estiloNivel(Nivel n) => switch (n) {
      Nivel.normal => const EstiloNivel('Normal', Color(0xFF1B5E20), Color(0xFF2E7D32), Colors.white,
          Color(0xFF1B5E20), Color(0xFF81C784), Icons.check_circle),
      Nivel.atencion => const EstiloNivel('Atención', Color(0xFFFFD600), Color(0xFFFFD600), _tinta,
          Color(0xFF7A5F00), Color(0xFFFFD600), Icons.visibility),
      Nivel.alerta => const EstiloNivel('Alerta', Color(0xFFEF6C00), Color(0xFFEF6C00), _tinta,
          Color(0xFFA84300), Color(0xFFFF9F40), Icons.warning),
      Nivel.evacuacion => const EstiloNivel('Evacuación', Color(0xFFB71C1C), Color(0xFFC62828), Colors.white,
          Color(0xFFB71C1C), Color(0xFFFF8A80), Icons.report),
      Nivel.sinDato => const EstiloNivel('Sin dato', Color(0xFF424242), Color(0xFF5A6570), Colors.white,
          Color(0xFF424242), Color(0xFFBDBDBD), Icons.help),
    };

/// Lo que el lector de pantalla dice de la escala de niveles de Inicio.
String descripcionEscala(double alturaM, String cuando, bool viejo, Umbrales u) {
  String metros(double m) => '${formatoAltura(m)} metros';
  final partes = <String>[
    viejo
        ? 'Escala de niveles. La última medición fue de ${metros(alturaM)}, $cuando.'
        : 'Escala de niveles. El río está en ${metros(alturaM)}, medido $cuando.',
  ];
  for (final (nombre, umbral) in [('atención', u.atencionM), ('alerta', u.alertaM), ('evacuación', u.evacuacionM)]) {
    if (umbral == null) continue;
    final falta = umbral - alturaM;
    partes.add(falta <= 0
        ? 'Nivel de $nombre: ${metros(umbral)}, ya superado.'
        : 'Nivel de $nombre: ${metros(umbral)}, faltan '
            '${falta < 1 ? '${(falta * 100).round()} centímetros' : metros(falta)}.');
  }
  return partes.join(' ');
}

/// Frase que acompaña al nivel: una oración corta. Cuánto falta para el nivel
/// siguiente se dice en la escalera de niveles. Con [viejo] (dato de hace más de
/// unas horas) se habla en pasado.
String descripcionNivel(Nivel n, Umbrales? u, {bool viejo = false}) {
  final siguiente = u?.atencionM != null ? 'atención' : 'alerta';
  if (viejo) {
    return switch (n) {
      Nivel.normal => 'Con el último dato, el río estaba por debajo del nivel de $siguiente.',
      Nivel.atencion => 'Con el último dato, el río estaba sobre el nivel de atención.',
      Nivel.alerta => 'Con el último dato, el río estaba sobre el nivel de alerta.',
      Nivel.evacuacion => 'Con el último dato, el río estaba sobre el nivel de evacuación. '
          'Si hay personas en peligro, llamá al 911.',
      Nivel.sinDato => 'No se puede saber el nivel actual del río.',
    };
  }
  return switch (n) {
    Nivel.normal => 'El río está por debajo del nivel de $siguiente.',
    Nivel.atencion => 'El río pasó el nivel de atención.',
    Nivel.alerta => 'El río pasó el nivel de alerta.',
    Nivel.evacuacion => 'El río pasó el nivel de evacuación. La orden de evacuar la da el Cecoed. '
        'Si hay personas en peligro, llamá al 911.',
    Nivel.sinDato => 'No hay un dato reciente. Esto no quiere decir que el río esté bajo.',
  };
}

/// "hoy 13:32" -> "Hoy 13:32"
String conMayuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Nombre corto de la fuente para el renglón que va debajo del número.
String fuenteCorta(String? fuente) {
  final f = (fuente ?? '').toLowerCase();
  if (f.contains('estación')) return 'CARU, estación automática';
  if (f.contains('prefectura')) return 'CARU, lectura de Prefectura';
  return 'CARU';
}

/// Los umbrales que existen, de mayor a menor: (nivel, altura).
List<(Nivel, double)> umbralesOrdenados(Umbrales u) => [
      if (u.evacuacionM != null) (Nivel.evacuacion, u.evacuacionM!),
      if (u.alertaM != null) (Nivel.alerta, u.alertaM!),
      if (u.atencionM != null) (Nivel.atencion, u.atencionM!),
    ];

/// "Faltan 93 cm para evacuación", "31 cm por encima de evacuación" o
/// "En el nivel de alerta". Es una resta entre valores publicados, no una
/// estimación. Devuelve null si no hay ningún umbral.
String? textoFalta(double alturaM, Umbrales u, {bool viejo = false}) {
  final lista = umbralesOrdenados(u);
  if (lista.isEmpty) return null;
  int cm(double m) => (m * 100).round();
  String nombre(Nivel n) => estiloNivel(n).nombre.toLowerCase();
  // El umbral más bajo que todavía está por encima del río.
  final arriba = lista.where((x) => cm(x.$2) > cm(alturaM)).toList();
  if (arriba.isNotEmpty) {
    final (nivel, valor) = arriba.last;
    final uno = cm(valor - alturaM) == 1;
    final verbo = viejo ? (uno ? 'Faltaba' : 'Faltaban') : (uno ? 'Falta' : 'Faltan');
    return '$verbo ${formatoDiferencia(valor - alturaM)} para ${nombre(nivel)}';
  }
  final (nivel, valor) = lista.first;
  if (cm(alturaM - valor) == 0) return '${viejo ? 'Estaba en' : 'En'} el nivel de ${nombre(nivel)}';
  final cuanto = formatoDiferencia(alturaM - valor);
  return viejo ? 'Estaba $cuanto por encima de ${nombre(nivel)}' : '$cuanto por encima de ${nombre(nivel)}';
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

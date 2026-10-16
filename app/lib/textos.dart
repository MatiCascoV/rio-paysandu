/// Textos y formatos que ve el vecino. Todo en español rioplatense, sin tecnicismos.
library;

import 'dart:math' as math;

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
/// Se decide con centímetros enteros: 0,999… m es "1,00 m", no "100 cm".
String formatoDiferencia(double metros) =>
    _cm(metros).abs() < 100 ? _centimetros(metros) : '${formatoAltura(_cm(metros).abs() / 100)} m';

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

  /// Color del nivel para trazos sobre el fondo de la app, como las líneas del
  /// gráfico. Tono oscuro en modo claro y claro en modo oscuro.
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

/// Contraste entre dos colores opacos (de 1 a 21), como lo mide WCAG.
double contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Colores de Inicio para cada nivel: la pantalla se tiñe apenas con el color
/// del nivel, el nombre va grande en un tono de la misma familia que se lee
/// bien sobre ese tinte, y el agua (las olas) usa el color fuerte.
abstract final class ColoresNivel {
  /// Color pleno del nivel: botón de "Ver qué hacer" y olas.
  static Color fuerte(Nivel n) => switch (n) {
        Nivel.normal => const Color(0xFF1B5E20),
        Nivel.atencion => const Color(0xFFFFD600),
        Nivel.alerta => const Color(0xFFEF6C00),
        Nivel.evacuacion => const Color(0xFFB71C1C),
        Nivel.sinDato => const Color(0xFF5B6770),
      };

  /// Tono para el nombre del nivel y su ícono, sobre el tinte.
  static Color familia(Nivel n) => Colores.oscuro
      ? switch (n) {
          Nivel.normal => const Color(0xFF81C784),
          Nivel.atencion => const Color(0xFFFFD600),
          Nivel.alerta => const Color(0xFFFF9F40),
          Nivel.evacuacion => const Color(0xFFFF8A80),
          Nivel.sinDato => const Color(0xFFBDBDBD),
        }
      : switch (n) {
          Nivel.normal => const Color(0xFF1B5E20),
          Nivel.atencion => const Color(0xFF6B5800),
          Nivel.alerta => const Color(0xFF9A3F00),
          Nivel.evacuacion => const Color(0xFF8E1515),
          Nivel.sinDato => const Color(0xFF44525E),
        };

  /// Tinte de arriba de la pantalla: el color fuerte al 16 % sobre blanco
  /// (claro) o al 22 % sobre el azul noche (oscuro).
  static Color tinte(Nivel n) => Colores.oscuro
      ? Color.lerp(const Color(0xFF0E1A24), fuerte(n), 0.22)!
      : Color.lerp(const Color(0xFFFFFFFF), fuerte(n), 0.16)!;

  /// Fondo y texto del botón "Ver qué hacer".
  static (Color, Color) boton(Nivel n) {
    if (Colores.oscuro) return (familia(n), const Color(0xFF0E1A24));
    final claroDeFondo = n == Nivel.atencion || n == Nivel.alerta; // amarillo y naranja
    return (fuerte(n), claroDeFondo ? const Color(0xFF111B24) : Colors.white);
  }

  /// Opacidad base de cada una de las tres capas de agua.
  static double get opacidadBase => Colores.oscuro ? 0.26 : 0.18;

  /// Color que queda donde se superponen [opacidades] capas de agua sobre el tinte.
  static Color bajoElAgua(Nivel n, List<double> opacidades) {
    var c = tinte(n);
    for (final a in opacidades) {
      c = Color.lerp(c, fuerte(n), a)!;
    }
    return c;
  }

  /// Opacidad de las tres capas de agua (de atrás hacia adelante). El agua
  /// puede quedar detrás del número, así que la tinta y la tinta secundaria
  /// tienen que leerse a 4,5:1 sobre las tres capas juntas. Si no alcanza, se
  /// bajan primero las dos de adelante y, solo si hace falta, la primera.
  static List<double> opacidadesOlas(Nivel n) {
    final base = opacidadBase;
    bool pasa(List<double> a) {
      final fondo = bajoElAgua(n, a);
      return contraste(Colores.tinta, fondo) >= 4.5 && contraste(Colores.tintaSecundaria, fondo) >= 4.5;
    }

    var a = [base, base, base];
    for (var paso = 0; !pasa(a) && a[1] > 0; paso++) {
      final arriba = math.max(0.0, base - 0.01 * (paso + 1));
      a = [base, arriba, arriba];
    }
    for (var paso = 0; !pasa(a) && a[0] > 0; paso++) {
      a = [math.max(0.0, base - 0.01 * (paso + 1)), 0, 0];
    }
    return a;
  }
}

/// Frase que acompaña al nivel: qué umbral pasó el río y cuánto falta para el
/// siguiente, con las alturas publicadas. Sin [alturaM] o sin umbrales queda la
/// frase sin cifras. Con [viejo] (dato de hace más de unas horas) se habla en pasado.
/// Con [umbralesInvalidos] (aviso del lector) y un dato fresco, se explica por
/// qué no hay nivel aunque haya altura.
String descripcionNivel(Nivel n, Umbrales? u,
    {double? alturaM, bool viejo = false, bool umbralesInvalidos = false}) {
  if (n == Nivel.sinDato && umbralesInvalidos && alturaM != null && !viejo) {
    return 'Hay un dato reciente, pero no se puede calcular el nivel: '
        'los niveles de referencia llegaron con un error.';
  }
  final cifras = u == null || alturaM == null ? null : _fraseConCifras(n, u, alturaM, viejo);
  if (cifras != null) return cifras;
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

/// Nivel que corresponde a [alturaM] con los umbrales [u], con la misma regla
/// que el lector (altura >= umbral, en centímetros enteros).
Nivel nivelSegunUmbrales(double alturaM, Umbrales u) {
  for (final (nivel, valor) in umbralesOrdenados(u)) {
    if (_cm(alturaM) >= _cm(valor)) return nivel;
  }
  return Nivel.normal;
}

/// La frase con umbrales y cifras, o null si falta el umbral que nombra o si
/// las cifras no cuadran con el nivel publicado (mejor sin cifras que contradictoria).
String? _fraseConCifras(Nivel n, Umbrales u, double alturaM, bool viejo) {
  if (n == Nivel.sinDato || nivelSegunUmbrales(alturaM, u) != n) return null;
  String umbral(Nivel x, double valor) => '${estiloNivel(x).nombre.toLowerCase()} (${formatoAltura(valor)} m)';
  final antes = viejo ? 'Con el último dato, el río estaba' : 'El río';
  final siguiente = _siguienteUmbral(alturaM, u);
  switch (n) {
    case Nivel.normal:
      if (siguiente == null) return null;
      final (nivel, valor) = siguiente;
      return '$antes${viejo ? '' : ' está'} por debajo del nivel de ${umbral(nivel, valor)}. '
          '${_verboFalta(valor - alturaM, viejo)} ${formatoDiferencia(valor - alturaM)}.';
    case Nivel.atencion || Nivel.alerta:
      final pasado = n == Nivel.atencion ? u.atencionM : u.alertaM;
      if (pasado == null) return null;
      // Justo en el umbral se dice "llegó", como en evacuación.
      final justo = _cm(alturaM) == _cm(pasado);
      final verbo = viejo ? (justo ? 'en el' : 'sobre el') : (justo ? 'llegó al' : 'pasó el');
      final frase = '$antes $verbo nivel de ${umbral(n, pasado)}.';
      // El siguiente solo si queda por encima del que pasó (el dato puede venir desparejo).
      if (siguiente == null || _cm(siguiente.$2) <= _cm(pasado)) return frase;
      return '$frase ${textoFalta(alturaM, u, viejo: viejo)} (${formatoAltura(siguiente.$2)} m).';
    case Nivel.evacuacion:
      final valor = u.evacuacionM;
      if (valor == null) return null;
      final exceso = _cm(alturaM) - _cm(valor);
      final donde = umbral(Nivel.evacuacion, valor);
      final cuanto = formatoDiferencia(alturaM - valor);
      if (viejo) {
        final frase = exceso > 0
            ? '$antes $cuanto por encima del nivel de $donde.'
            : exceso == 0
                ? '$antes en el nivel de $donde.'
                : '$antes sobre el nivel de $donde.';
        return '$frase Si hay personas en peligro, llamá al 911.';
      }
      final frase = exceso > 0
          ? 'El río pasó el nivel de $donde por $cuanto.'
          : exceso == 0
              ? 'El río llegó al nivel de $donde.'
              : 'El río pasó el nivel de $donde.';
      return '$frase La orden de evacuar la da el Cecoed. Si hay personas en peligro, llamá al 911.';
    case Nivel.sinDato:
      return null;
  }
}

/// El mismo texto con las unidades en palabras, para el lector de pantalla:
/// "4,39 m" -> "4,39 metros", "81 cm" -> "81 centímetros".
String unidadesEnPalabras(String texto) => texto
    .replaceAllMapped(RegExp(r'(\d+,\d+) m\b'), (m) => '${m[1]} metros')
    .replaceAllMapped(RegExp(r'(\d+) cm\b'), (m) => m[1] == '1' ? '1 centímetro' : '${m[1]} centímetros');

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
  String nombre(Nivel n) => estiloNivel(n).nombre.toLowerCase();
  final siguiente = _siguienteUmbral(alturaM, u);
  if (siguiente != null) {
    final (nivel, valor) = siguiente;
    return '${_verboFalta(valor - alturaM, viejo)} ${formatoDiferencia(valor - alturaM)} para ${nombre(nivel)}';
  }
  final (nivel, valor) = lista.first;
  if (_cm(alturaM - valor) == 0) return '${viejo ? 'Estaba en' : 'En'} el nivel de ${nombre(nivel)}';
  final cuanto = formatoDiferencia(alturaM - valor);
  return viejo ? 'Estaba $cuanto por encima de ${nombre(nivel)}' : '$cuanto por encima de ${nombre(nivel)}';
}

/// Las comparaciones con los umbrales se hacen en centímetros enteros.
int _cm(double m) => (m * 100).round();

/// El umbral más bajo que todavía está por encima del río, o null.
(Nivel, double)? _siguienteUmbral(double alturaM, Umbrales u) {
  final arriba = umbralesOrdenados(u).where((x) => _cm(x.$2) > _cm(alturaM));
  return arriba.isEmpty ? null : arriba.last;
}

/// "Falta" o "Faltan" ("Faltaba", "Faltaban" en pasado) según la diferencia.
String _verboFalta(double metros, bool viejo) {
  final uno = _cm(metros) == 1;
  return viejo ? (uno ? 'Faltaba' : 'Faltaban') : (uno ? 'Falta' : 'Faltan');
}

/// Explicación de cada aviso que manda el lector. Los que no conocemos no se muestran.
String? textoAviso(String codigo) => switch (codigo) {
      'dato_desactualizado' => 'Este dato puede estar desactualizado. Fijate en la fecha y la hora.',
      'estacion_desactualizada' =>
        'La estación automática no está informando. Se muestra la lectura de Prefectura.',
      'dato_a_verificar' => 'Este dato puede tener un error. Puede cambiar cuando CARU lo revise.',
      'dato_fuera_de_rango' => 'Llegó un dato con error y no se muestra.',
      'fuente_no_disponible' => 'No llegó información nueva de CARU. Se muestra el último dato que hay.',
      'umbrales_invalidos' =>
        'Los niveles de referencia que llegaron tienen un error; no se usan para calcular el nivel.',
      'pronostico_no_disponible' =>
        'No se pudo leer el último informe de CARU; el pronóstico puede no estar al día.',
      _ => null,
    };

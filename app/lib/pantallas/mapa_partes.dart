/// Partes de la pestaña Mapa que no son el dibujo del mapa: franja de hoy,
/// aviso único, lectura (hoy o simulación), marco del mapa, control de
/// altura, botones de alturas, leyenda, "Cómo se usa" y fuentes.
///
/// Diseño: docs/mapa/09-diseno-pantalla.md. El dibujo (colores, rayado,
/// muestras de la leyenda) está en mapa/estilo_mapa.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../datos.dart';
import '../mapa/logica_mapa.dart';
import '../mapa/modelos_mapa.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

// ---------------------------------------------------------------------------
// Textos

/// Atribución que va siempre a la vista sobre el mapa.
const textoAtribucion = '© OpenStreetMap · IDE Uruguay · Dinagua';

/// Aviso corto pegado debajo del mapa (pie del marco). Siempre a la vista.
const textoAvisoMapa = 'Aproximado. No reemplaza la alerta oficial.';

const textoMapaNoDisponible = 'El mapa todavía no está disponible';

/// Sello del mapa cuando el índice dice `validado: false`.
const textoMapaEnPrueba = 'Mapa en prueba: el agua puede llegar más lejos de lo que muestra.';

/// Sello del mapa cuando los archivos son los provisorios (agua inventada).
const textoMapaProvisorio = 'Datos de prueba: el agua es inventada. No la uses para decidir nada.';

const textoTituloAproximado = 'Este mapa es aproximado';

/// Aviso fijo del pie (01 §6, 04 §3.2 y condición 2 y 5 del control 11 §8):
/// estimación no oficial, el borde puede variar una cuadra o más, no incluye
/// lluvia, pluviales ni arroyos, quedar rodeado de agua también es riesgo, y
/// no reemplaza al Cecoed ni a la Intendencia.
const textoMapaAproximado =
    'Es una estimación comunitaria, no un mapa oficial. Muestra hasta dónde podría llegar el río con esa '
    'altura, según el terreno de 2017–2018 y crecidas medidas por Dinagua. El borde puede variar una cuadra '
    'o más. No tiene en cuenta la lluvia, los desagües y pluviales, las crecidas propias de los arroyos ni '
    'las calles cortadas. Que una calle no aparezca con agua no quiere decir que no se inunde: si estás cerca '
    'del borde, el agua te puede llegar. Si quedás rodeado de agua, también estás en riesgo. No reemplaza los '
    'avisos del Cecoed ni de la Intendencia. Emergencias: 911.';

const textoDatosMapa = 'Datos: OpenStreetMap, IDE Uruguay, Dinagua y CARU.';

const pasosComoSeUsa = [
  'Mové la barra o tocá − y + para elegir una altura del río.',
  'El mapa pinta hasta dónde llegaría el agua con esa altura.',
  'Para mover el mapa, tocá las flechas de abajo del mapa o usá dos dedos. Con + y − se acerca y se aleja.',
  'Es aproximado: el agua puede llegar más lejos. No reemplaza la alerta oficial.',
];

/// Hoja "Fuentes": solo texto, sin enlaces (decisión del 21/10/2026). Textos
/// de docs/mapa/13-legal.md §3.3: aviso ODbL de la base derivada de OSM (B1),
/// nota de origen de la IDE con los dos productos MDT y las modificaciones
/// (B3) y Dinagua sin licencia publicada (B2). El detalle completo está en
/// assets/mapa/LICENSE-DATOS.md.
const textosFuentes = [
  (
    'Calles, río y barrios',
    '© colaboradores de OpenStreetMap. Los usamos para el fondo y para calcular el agua; '
        'esos datos derivados se comparten con la misma licencia, ODbL 1.0 '
        '(openstreetmap.org/copyright).',
  ),
  (
    'Terreno',
    'IDE Uruguay: modelo digital del terreno urbano de Paysandú, 1 m (vuelo de 2017), y nacional, 2,5 m '
        '(vuelo 2017–2018), del conjunto "Ortoimagen y modelo digital del terreno de cobertura nacional". '
        'Licencia de Datos Abiertos – Uruguay (catalogodatos.gub.uy). Datos modificados: los recortamos, '
        'unimos y pasamos a 2 m, y calculamos qué partes quedan por debajo de cada altura del río.',
  ),
  (
    'Crecidas medidas',
    'Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. '
        'Información pública; Dinagua no publicó una licencia para estas capas y le estamos consultando. '
        'Las recortamos y simplificamos.',
  ),
  ('Altura del río y pronóstico', 'Comisión Administradora del Río Uruguay (CARU).'),
];

const textoFuentesDeslinde =
    'Los datos fueron modificados por Mi Río UY. Ni el Ministerio de Ambiente, ni la IDE, ni CARU, '
    'ni OpenStreetMap avalan esta app ni son responsables de lo que muestra.';

/// Alto del mapa: 40 % de la pantalla, entre estos dos topes.
const altoMapa = 320.0;
const altoMapaMinimo = 240.0;

/// Aviso que aparece un momento si alguien arrastra el mapa con un dedo: con
/// un dedo se mueve la pantalla (para no quedar atrapado en el mapa).
const textoDosDedos = 'Para mover el mapa usá dos dedos o las flechas de abajo.';

/// Zona baja de la costa (contrato v1.1 §3): con la altura en `min_m` o por
/// debajo, el agua no pasa de ahí. Nunca "en su cauce": esa capa ya moja
/// islas y bañados (unas 450 ha).
const textoZonaBaja =
    'Con esta altura el agua no pasa de la zona baja de la costa: islas y bañados que se mojan con el río normal.';

/// Se agrega a [textoZonaBaja] cuando el margen está dibujado.
const textoZonaBajaMargen = 'Los puntos muestran hasta dónde podría llegar con un poco más.';

/// Fila de la leyenda de la zona baja (sin la palabra del dibujo).
const textoLeyendaZonaBaja = 'Zona baja de la costa: se moja con el río normal';

/// Loma rodeada de agua (contrato v1.1 §2), al tocar su marca.
const textoLomaAislada = 'Quedaría rodeada de agua: aunque no se inunde, puede quedar aislada.';

/// Aviso de la lectura cuando la capa pintada tiene lomas aisladas.
String textoAvisoAisladas(int cuantas) => cuantas == 1
    ? 'Hay una loma marcada en el mapa. $textoLomaAislada'
    : 'Hay $cuantas lomas marcadas en el mapa. Quedarían rodeadas de agua: aunque no se inunden, '
          'pueden quedar aisladas.';

/// Zona sin validar (contrato v1.1 §1): resumen textual cuando no se conocen
/// los nombres de las zonas. Para la v1 hay una sola: el valle del arroyo
/// San Francisco Grande (contrato 05, v1.1 §1; 11 §8, condición 3).
const textoSinValidar = 'En el valle del arroyo San Francisco Grande el mapa no se pudo comparar con crecidas reales.';

/// Se agrega a [textoSinValidar] cuando la zona no está dibujada (el índice no
/// trae `sin_validar` o el archivo no validó): la zona existe igual y hay que
/// decirlo (11 §8, condición 3), aunque no haya borde para mostrar.
const textoSinValidarSinDibujo = 'Esa zona no está marcada en el dibujo.';

/// Fila de la leyenda, sin muestra, cuando la zona sin validar no está
/// dibujada. No repite la fila del borde ([textoLeyendaSinValidar]).
const textoLeyendaSinValidarSinDibujo =
    'Valle del arroyo San Francisco Grande: zona sin validar, el mapa no la pudo comparar con crecidas. '
    'No está marcada en el dibujo';

/// Resumen textual de la zona sin validar con los nombres que trae
/// `sin_validar.json`, para no nombrar un lugar que no es si el pipeline
/// agrega o cambia zonas. Sin nombres, [textoSinValidar].
String textoSinValidarDe(List<String> nombres) {
  final n = [
    for (final x in nombres)
      if (x.trim().isNotEmpty) x.trim(),
  ];
  if (n.isEmpty) return textoSinValidar;
  final lista = n.length == 1 ? n.single : '${n.sublist(0, n.length - 1).join(', ')} y ${n.last}';
  return n.length == 1
      ? 'Zona sin validar: $lista. Ahí el mapa no se pudo comparar con crecidas reales.'
      : 'Zonas sin validar: $lista. Ahí el mapa no se pudo comparar con crecidas reales.';
}

/// Fila de la leyenda de la zona sin validar (sin la palabra del dibujo).
const textoLeyendaSinValidar = 'Zona sin validar: el mapa no se pudo comparar con crecidas reales';

/// Fila de la leyenda de las lomas aisladas (sin la palabra del dibujo).
const textoLeyendaAisladas = 'Loma que quedaría rodeada de agua: puede quedar aislada';

/// Fila de la leyenda de la línea de hoy (sin la palabra del dibujo), al
/// simular otra altura. Con un dato viejo o sin conexión,
/// [textoLeyendaUltimoDato].
const textoLeyendaHoy = 'Hasta dónde llega el agua con el río de hoy';
const textoLeyendaUltimoDato = 'Hasta dónde llega el agua con el último dato';

/// Fila de la leyenda del margen, cuando entra entero en el mapa.
String textoLeyendaMargen(int margenCm) =>
    'Puede llegar un poco más: hasta ${formatoDiferencia(margenCm / 100)} más de altura';

/// Fila de la leyenda del margen cuando altura + margen pasa del máximo del
/// mapa: los puntos quedan recortados (o pegados al agua) y no muestran todo
/// el margen.
String textoLeyendaMargenRecortado(int maxCm) =>
    'Puede llegar un poco más. Los puntos se cortan en ${formatoAltura(maxCm / 100)} m, donde termina el mapa: '
    'con un poco más de altura, el agua puede pasarlos';

/// Línea de la lectura (con aviso) cuando el margen quedó recortado en el
/// máximo del mapa, dentro del rango (por encima ya hay otro aviso).
String textoMargenRecortado(int maxCm) =>
    'El mapa llega hasta ${formatoAltura(maxCm / 100)} m: con un poco más de altura, '
    'el agua puede pasar los puntos y llegar más lejos de lo que se ve.';

/// Cuando la capa de agua de esta altura (y las de arriba) no se pudo leer: el
/// dibujo no sirve para esta altura y se tapa con este aviso.
const textoDibujoIlegible =
    'No se pudo leer el dibujo del agua para esta altura. El mapa no muestra hasta dónde llegaría: '
    'el agua puede llegar lejos. Seguí los avisos oficiales.';

/// Clave de SharedPreferences: la tarjeta "Cómo se usa" ya se vio.
const claveComoSeUsa = 'mapa_como_se_usa_visto';

// ---------------------------------------------------------------------------
// El río de hoy

/// La altura del río que el mapa puede usar como "hoy".
class HoyMapa {
  /// null si no hay un dato que se pueda pintar (ver [motivo]).
  final Lectura? lectura;
  final Nivel nivel;
  final bool viejo;
  final bool sinConexion;

  /// Por qué no hay "hoy": 'sin_dato' o 'cero' (el mapa usa otra referencia).
  final String? motivo;

  /// Avisos del lector que conviene repetir (por ejemplo dato_a_verificar).
  final List<String> avisos;

  const HoyMapa({
    this.lectura,
    this.nivel = Nivel.sinDato,
    this.viejo = false,
    this.sinConexion = false,
    this.motivo,
    this.avisos = const [],
  });

  bool get hay => lectura != null;

  /// "Último dato" en vez de "hoy": dato viejo o guardado sin conexión.
  bool get esUltimoDato => viejo || sinConexion;

  /// Nivel grave de hoy (para "Ver qué hacer").
  bool get grave => hay && (nivel == Nivel.alerta || nivel == Nivel.evacuacion);
}

/// Decide qué altura de hoy se puede pintar, con los mismos criterios que
/// Inicio: nivel vigente, dato viejo, sin conexión, y además que el mapa y
/// actual.json usen el mismo cero.
HoyMapa hoyParaMapa(Datos? datos, Config config, IndiceMapa indice, DateTime ahora) {
  final actual = datos?.actual;
  final altura = actual?.altura;
  final sinConexion = datos?.sinConexion ?? false;
  if (actual == null || altura == null) return HoyMapa(sinConexion: sinConexion, motivo: 'sin_dato');
  // Misma regla que nivelVigente (dato muy viejo o posterior a "generado"),
  // aunque el lector no haya podido calcular el nivel.
  final usable =
      Actual(altura: altura, generado: actual.generado, nivel: Nivel.normal).nivelVigente(ahora, config.horasSinDato) !=
      Nivel.sinDato;
  if (!usable) return HoyMapa(sinConexion: sinConexion, motivo: 'sin_dato');
  if (actual.cero != indice.cero) return HoyMapa(sinConexion: sinConexion, motivo: 'cero');
  return HoyMapa(
    lectura: altura,
    nivel: actual.nivelVigente(ahora, config.horasSinDato),
    viejo: ahora.difference(altura.fecha).inMinutes / 60 > config.horasAvisoDatoViejo,
    sinConexion: sinConexion,
    avisos: actual.avisos,
  );
}

// ---------------------------------------------------------------------------
// Avisos: uno solo para el dato de hoy; la calidad del mapa va en el sello.

typedef Aviso = ({IconData icono, String texto});

/// El aviso del dato de hoy que va en el único recuadro ámbar, o null.
/// Prioridad (09 §4): otra referencia > sin dato > dato viejo > dato a verificar.
/// "Sin conexión" con un dato fresco no es recuadro: va en la franja.
Aviso? avisoHoyMapa(HoyMapa hoy, DateTime ahora) {
  if (hoy.motivo == 'cero') {
    return (
      icono: Icons.straighten,
      texto:
          'El mapa usa otra referencia de altura que el dato del río. Por eso no se pinta el río de hoy. '
          'Igual podés probar alturas.',
    );
  }
  if (!hoy.hay) {
    return (
      icono: hoy.sinConexion ? Icons.wifi_off : Icons.help_outline,
      texto:
          '${hoy.sinConexion ? 'Sin conexión y sin' : 'No hay'} un dato confiable de hoy. '
          'Esto no quiere decir que el río esté bajo. Igual podés probar alturas.',
    );
  }
  if (hoy.viejo) {
    return (
      icono: Icons.schedule,
      texto:
          'El último dato es de ${formatoFecha(hoy.lectura!.fecha, ahora)}. '
          'El río pudo cambiar: mirá Inicio o los canales oficiales.',
    );
  }
  if (hoy.avisos.contains('dato_a_verificar')) {
    return (icono: Icons.warning_amber, texto: textoAviso('dato_a_verificar')!);
  }
  return null;
}

/// Sello de calidad del mapa (arriba del dibujo): provisorio > en prueba > nada.
({IconData icono, String texto, bool fuerte})? selloMapa(IndiceMapa indice) {
  if (indice.modelo.esProvisorio) return (icono: Icons.science_outlined, texto: textoMapaProvisorio, fuerte: true);
  if (!indice.validado) return (icono: Icons.construction, texto: textoMapaEnPrueba, fuerte: false);
  return null;
}

// ---------------------------------------------------------------------------
// El mapa en palabras (para TalkBack): el dibujo no se puede recorrer por voz.

String _metros(int cm) => '${formatoAltura(cm / 100)} metros';

/// Resumen textual equivalente al dibujo: qué altura se pinta, la zona baja,
/// qué significan el rayado y los puntos, las lomas aisladas, la zona sin
/// validar y que el agua puede llegar más lejos. No nombra calles ni barrios
/// (09 §9, decisión 3): una lista incompleta se leería como "ahí no llega".
///
/// [minCm] es la capa más baja (zona baja de la costa); [zonaBajaDibujada]
/// dice si esa capa se pudo leer. [aisladas] es la cantidad de lomas
/// marcadas; [sinValidar] dice si la zona sin validar está dibujada, y
/// [nombresSinValidar], sus nombres (de `sin_validar.json`);
/// [sinValidarSinDibujo], que la zona existe pero no está dibujada (se nombra
/// igual, 11 §8 condición 3); [margenRecortado], que altura + margen pasa del
/// máximo del mapa; [hoyCm], la altura de la línea "agua de hoy" si está
/// dibujada.
String resumenMapa({
  required SituacionAgua? situacion,
  required int? alturaCm,
  required int? dibujoCm,
  required int? margenCm,
  required int minCm,
  required int maxCm,
  bool zonaBajaDibujada = true,
  bool simulacion = false,
  bool dibujoIlegible = false,
  int aisladas = 0,
  bool sinValidar = false,
  List<String> nombresSinValidar = const [],
  bool sinValidarSinDibujo = false,
  bool margenRecortado = false,
  int? hoyCm,
  String? contorno,
}) {
  final partes = <String>['Mapa de la costa de Paysandú, con el río, las calles y los barrios.'];
  if (simulacion) partes.add('Simulación: no es el río de hoy.');
  final masDeAltura = margenCm == null || dibujoCm == null && alturaCm == null
      ? null
      : unidadesEnPalabras('${formatoDiferencia((margenCm - (dibujoCm ?? alturaCm!)) / 100)} más de altura');
  final noPasa = alturaCm != null && alturaCm <= minCm;
  if (situacion != null && noPasa) {
    // Igual con 3,90 que con 4,00: sin salto de texto en el mínimo.
    partes.add(
      'Con ${_metros(alturaCm)} el agua no pasa de la zona baja de la costa: '
      'islas y bañados que se mojan con el río normal.',
    );
    if (!zonaBajaDibujada) partes.add('No se pudo leer el dibujo de la zona baja de la costa.');
    if (margenCm != null && margenCm > alturaCm) {
      partes.add('Los puntos muestran hasta dónde podría llegar con un poco más.');
    }
  } else if (situacion != null) {
    if (dibujoIlegible || dibujoCm == null) {
      partes.add('No se pudo leer el dibujo del agua para esta altura.');
    } else {
      partes.add('Agua dibujada con ${_metros(dibujoCm)}: el rayado muestra hasta dónde llegaría.');
      if (masDeAltura != null && margenCm! > dibujoCm) {
        partes.add('Los puntos, hasta dónde puede llegar con $masDeAltura.');
      }
    }
    if (zonaBajaDibujada) {
      partes.add('La zona baja de la costa, que se moja con el río normal, tiene su propio dibujo.');
    }
    if (situacion == SituacionAgua.sobreMaximo) {
      partes.add(
        'El mapa llega hasta ${_metros(maxCm)}. Con ${_metros(alturaCm!)} el agua llega más lejos de lo que se ve.',
      );
    } else if (margenRecortado) {
      partes.add(unidadesEnPalabras(textoMargenRecortado(maxCm)));
    }
  }
  if (aisladas > 0) partes.add(textoAvisoAisladas(aisladas));
  if (sinValidar) {
    partes.add(textoSinValidarDe(nombresSinValidar));
  } else if (sinValidarSinDibujo) {
    partes.add('$textoSinValidar $textoSinValidarSinDibujo');
  }
  if (hoyCm != null) partes.add('Línea gruesa: hasta dónde llega el agua con el río de hoy, ${_metros(hoyCm)}.');
  if (contorno != null) partes.add('Línea de trazos: el borde medido en la crecida "$contorno".');
  partes.add(
    'Es aproximado: el agua puede llegar más lejos. Este resumen no dice qué calles o barrios alcanza el agua.',
  );
  return partes.join(' ');
}

/// Lo que se agrega al anuncio de la lectura cuando cambia la altura, para
/// decir qué pasó con el agua. null si la lectura ya lo dice (zona baja,
/// sobre el máximo, dibujo ilegible).
String? fraseAgua(EleccionAgua e, int? dibujoCm) =>
    e.situacion == SituacionAgua.enRango && !e.noPasaDeLaZonaBaja && dibujoCm != null
    ? 'El mapa ahora muestra el agua con ${_metros(dibujoCm)}. Puede llegar más lejos.'
    : null;

/// Hoja con el aviso de una loma aislada (al tocar su marca en el mapa).
Future<void> mostrarLomaAislada(BuildContext context, LomaAislada loma) => _hoja(context, (tema) {
  final ha = loma.hectareas;
  return [
    Semantics(header: true, child: Text('Loma rodeada de agua', style: tema.titleMedium)),
    const SizedBox(height: 8),
    Text(textoLomaAislada, style: tema.bodyLarge),
    if (ha != null) ...[
      const SizedBox(height: 8),
      Text(
        'Mide unas ${ha < 10 ? ha.toStringAsFixed(1).replaceAll('.', ',') : ha.round()} hectáreas.',
        style: tema.bodyMedium,
      ),
    ],
    const SizedBox(height: 8),
    Text(
      'Si quedás rodeado de agua, también estás en riesgo. Seguí las indicaciones del Cecoed.',
      style: tema.bodyLarge,
    ),
  ];
});

/// Colores del recuadro ámbar (los mismos de [Recuadro]).
Color get _fondoAmbar => Colores.oscuro ? const Color(0xFF3A2E12) : const Color(0xFFFFF4D6);
Color get _iconoAmbar => Colores.oscuro ? const Color(0xFFFFC857) : const Color(0xFF7A4A00);

/// Panel invertido de la simulación: oscuro en modo claro, claro en oscuro.
abstract final class ColoresSimulacion {
  static Color get fondo => Colores.oscuro ? const Color(0xFFEAF2F8) : const Color(0xFF0B2A3F);
  static Color get texto => Colores.oscuro ? const Color(0xFF0E1A24) : const Color(0xFFEEF4F8);
}

// ---------------------------------------------------------------------------
// Franja de hoy

class FranjaHoyMapa extends StatelessWidget {
  final HoyMapa hoy;
  final DateTime ahora;

  const FranjaHoyMapa({super.key, required this.hoy, required this.ahora});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final fuerte = tema.titleLarge?.copyWith(fontWeight: FontWeight.w800);
    final l = hoy.lectura;
    final nivel = l == null ? Nivel.sinDato : hoy.nivel;
    final estilo = estiloNivel(nivel);
    final color = ColoresNivel.familia(nivel);
    final rotulo = hoy.esUltimoDato ? 'Último dato' : 'Río hoy';
    final String primera;
    final String etiqueta;
    if (l != null) {
      final cuando = formatoFecha(l.fecha, ahora);
      primera = '$rotulo: ${formatoAltura(l.valorM)} m';
      etiqueta =
          '$rotulo: ${formatoAltura(l.valorM)} metros. Nivel: ${estilo.nombre}. '
          'Medido $cuando. Fuente: ${fuenteCorta(l.fuente)}.';
    } else if (hoy.motivo == 'cero') {
      primera = 'Río hoy: no se puede pintar';
      etiqueta = '$primera.';
    } else {
      primera = 'Río hoy: sin dato';
      etiqueta = '$primera.';
    }
    final sinConexion = hoy.sinConexion
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.wifi_off, size: 24, color: Colores.tinta),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l == null ? 'Sin conexión a internet.' : 'Sin conexión. Dato guardado en este teléfono.',
                    style: tema.titleMedium,
                  ),
                ),
              ],
            ),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          excludeSemantics: true,
          label: etiqueta,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(primera, style: fuerte),
                  if (hoy.motivo != 'cero')
                    // Ícono y palabra juntos: con letra muy grande el par baja
                    // de renglón entero y la palabra sigue siendo un texto.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(estilo.icono, color: color, size: 24),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(estilo.nombre, style: fuerte?.copyWith(color: color)),
                        ),
                      ],
                    ),
                ],
              ),
              if (l != null)
                Text(
                  '${conMayuscula(formatoFecha(l.fecha, ahora))} · ${fuenteCorta(l.fuente)}',
                  style: tema.bodyMedium,
                ),
            ],
          ),
        ),
        ?sinConexion,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "Cómo se usa"

class ContenidoComoSeUsa extends StatelessWidget {
  const ContenidoComoSeUsa({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Cómo se usa', style: tema.titleMedium)),
        const SizedBox(height: 6),
        for (final (i, paso) in pasosComoSeUsa.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}.', style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(child: Text(paso, style: tema.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de la primera vez, con "Entendido".
class TarjetaComoSeUsa extends StatelessWidget {
  final VoidCallback alEntender;

  const TarjetaComoSeUsa({super.key, required this.alEntender});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colores.superficie, borderRadius: radioSuperficie),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ContenidoComoSeUsa(),
        const SizedBox(height: 12),
        FilledButton(onPressed: alEntender, child: const Text('Entendido')),
      ],
    ),
  );
}

Future<void> _hoja(BuildContext context, List<Widget> Function(TextTheme tema) contenido) => showModalBottomSheet<void>(
  context: context,
  // "Quitar animaciones" de Android: la hoja aparece sin deslizarse.
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colores.superficie,
  showDragHandle: true,
  builder: (context) {
    final tema = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...contenido(tema),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  },
);

Future<void> mostrarComoSeUsa(BuildContext context) => _hoja(context, (_) => const [ContenidoComoSeUsa()]);

Future<void> mostrarFuentes(BuildContext context, IndiceMapa indice) => _hoja(context, (tema) {
  final generado = indice.generado;
  return [
    Semantics(header: true, child: Text('Fuentes del mapa', style: tema.titleMedium)),
    for (final (titulo, texto) in textosFuentes)
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$titulo: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: texto),
            ],
          ),
          style: tema.bodyLarge,
        ),
      ),
    if (indice.fuentes.isNotEmpty) ...[
      const SizedBox(height: 12),
      for (final f in indice.fuentes) Text(f, style: tema.bodyMedium),
    ],
    const SizedBox(height: 12),
    if (generado != null) Text('Mapa armado el ${formatoDia(enHoraUruguay(generado))}.', style: tema.bodyLarge),
    Text(textoFuentesDeslinde, style: tema.bodyLarge),
  ];
});

// ---------------------------------------------------------------------------
// Lectura: qué altura se está mirando

/// Un renglón debajo del número; [aviso] lo marca con ícono de atención.
typedef LineaLectura = ({String texto, bool aviso, bool chica});

/// Lo que dice la lectura, ya decidido (se usa también para el anuncio).
class DatosLectura {
  /// true: panel invertido "Simulación con"; false: "Altura de hoy en el mapa".
  final bool simulacion;

  /// "No es el río de hoy" / "No es el último dato" (solo en simulación).
  final String? titulo;
  final String rotulo;
  final double metros;

  /// Nivel de esa altura (pastilla), solo en simulación y fuera del cauce.
  final Nivel? nivel;
  final bool deReferencia;
  final List<LineaLectura> lineas;

  /// "Volver a hoy" / "Volver al último dato", o null.
  final String? textoVolver;

  const DatosLectura({
    required this.simulacion,
    required this.rotulo,
    required this.metros,
    this.titulo,
    this.nivel,
    this.deReferencia = false,
    this.lineas = const [],
    this.textoVolver,
  });

  /// Para el lector de pantalla, con las unidades en palabras.
  String get anuncio {
    final partes = <String>[
      ?titulo,
      // "Altura de hoy en el mapa: 4,20 metros" / "Simulación con 4,30 metros".
      '$rotulo${simulacion ? '' : ':'} ${formatoAltura(metros)} m'
          '${nivel == null ? '' : ', nivel ${estiloNivel(nivel!).nombre}${deReferencia ? ' (de referencia)' : ''}'}',
      for (final l in lineas) l.texto,
    ];
    return unidadesEnPalabras(partes.map((p) => p.endsWith('.') ? p : '$p.').join(' '));
  }
}

class LecturaMapa extends StatelessWidget {
  final DatosLectura datos;
  final VoidCallback? alVolver;

  const LecturaMapa({super.key, required this.datos, this.alVolver});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final d = datos;
    final tinta = d.simulacion ? ColoresSimulacion.texto : Colores.tinta;
    final secundaria = d.simulacion ? ColoresSimulacion.texto : Colores.tintaSecundaria;
    final numero = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '${formatoAltura(d.metros)} m',
          style: TextStyle(
            fontSize: 40,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: tinta,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    // Para TalkBack, un solo nodo con el texto en palabras ("metros", "nivel
    // Alerta"); el botón "Volver a hoy" queda aparte. Sin liveRegion: el
    // cambio se anuncia una vez al soltar o tocar (mapa.dart), no en cada
    // paso del arrastre.
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.titulo case final titulo?)
          Row(
            children: [
              Icon(Icons.science_outlined, color: tinta, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: tema.titleMedium?.copyWith(color: tinta, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        Text(d.rotulo, style: tema.bodyLarge?.copyWith(color: secundaria)),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            numero,
            if (d.nivel case final n?) PastillaNivel(nivel: n),
            if (d.nivel != null && d.deReferencia)
              Text('(de referencia)', style: tema.bodyMedium?.copyWith(color: tinta)),
          ],
        ),
        for (final l in d.lineas)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (l.aviso) ...[Icon(Icons.warning_amber, color: tinta, size: 24), const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    l.texto,
                    style: (l.chica ? tema.bodyMedium : tema.bodyLarge)?.copyWith(
                      color: tinta,
                      fontWeight: l.aviso ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(container: true, label: d.anuncio, excludeSemantics: true, child: textos),
        if (alVolver != null && d.textoVolver != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: alVolver,
            style: OutlinedButton.styleFrom(
              foregroundColor: tinta,
              side: BorderSide(color: tinta, width: 1.5),
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.undo),
            label: Text(d.textoVolver!, textAlign: TextAlign.center),
          ),
        ],
      ],
    );
    return d.simulacion
        ? Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: ColoresSimulacion.fondo, borderRadius: radioSuperficie),
            child: contenido,
          )
        : contenido;
  }
}

/// Ícono y palabra del nivel sobre su color pleno (contraste de 5:1 o más).
class PastillaNivel extends StatelessWidget {
  final Nivel nivel;

  const PastillaNivel({super.key, required this.nivel});

  @override
  Widget build(BuildContext context) {
    final e = estiloNivel(nivel);
    // Crece con la letra del teléfono (hasta 200 %, WCAG 1.4.4); si no entra,
    // la palabra baja de renglón dentro de la pastilla en vez de cortarse.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2.0,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: e.fondo, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(e.icono, color: e.texto, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                e.nombre.toUpperCase(),
                style: TextStyle(color: e.texto, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marco del mapa: sello arriba, el dibujo, pie abajo.

class MarcoMapa extends StatelessWidget {
  final IndiceMapa indice;
  final Widget mapa;

  /// Botones para mover el mapa sin arrastrar (WCAG 2.5.7), debajo del dibujo.
  final Widget? mover;

  const MarcoMapa({super.key, required this.indice, required this.mapa, this.mover});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final sello = selloMapa(indice);
    return ClipRRect(
      borderRadius: radioSuperficie,
      child: ColoredBox(
        color: Colores.superficie,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sello != null)
              Container(
                color: _fondoAmbar,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(sello.icono, color: _iconoAmbar, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sello.texto,
                        style: tema.bodyMedium?.copyWith(fontWeight: sello.fuerte ? FontWeight.w800 : FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            mapa,
            ?mover,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(Icons.info_outline, size: 20, color: Colores.tintaSecundaria)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(textoAvisoMapa, style: tema.bodyMedium)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flechas de 48 dp para mover el mapa sin arrastrar: para quien no puede
/// hacer el gesto (temblor, un solo dedo, TalkBack) y porque con un dedo sobre
/// el mapa se mueve la página. (dx, dy) en -1, 0, 1; y crece hacia el sur.
class FilaMoverMapa extends StatelessWidget {
  final void Function(int dx, int dy) alMover;

  const FilaMoverMapa({super.key, required this.alMover});

  static const flechas = [
    (Icons.arrow_back, 'Ver más al oeste, hacia el río', -1, 0),
    (Icons.arrow_upward, 'Ver más al norte', 0, -1),
    (Icons.arrow_downward, 'Ver más al sur', 0, 1),
    (Icons.arrow_forward, 'Ver más al este', 1, 0),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text('Mover el mapa', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (icono, texto, dx, dy)) in flechas.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: texto,
                onPressed: () => alMover(dx, dy),
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                icon: Icon(icono),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Control de altura

/// Marca de un umbral sobre la pista del deslizador.
typedef MarcaUmbral = ({Nivel nivel, double metros});

class ControlAltura extends StatelessWidget {
  final int cm;
  final int bajo;
  final int alto;
  final int paso;
  final List<MarcaUmbral> marcas;
  final bool deReferencia;

  /// Valor para TalkBack de una altura en cm ("4,20 metros, nivel Alerta").
  final String Function(int cm) valorParaLector;
  final ValueChanged<int> alCambiar;
  final VoidCallback alEmpezar;
  final VoidCallback alSoltar;
  final ValueChanged<int> alTocarPaso;

  const ControlAltura({
    super.key,
    required this.cm,
    required this.bajo,
    required this.alto,
    required this.paso,
    required this.marcas,
    required this.deReferencia,
    required this.valorParaLector,
    required this.alCambiar,
    required this.alEmpezar,
    required this.alSoltar,
    required this.alTocarPaso,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final pasoTexto = formatoDiferencia(paso / 100);
    final visibles = marcas.where((m) => aCm(m.metros) > bajo && aCm(m.metros) < alto).toList();
    final fracciones = [for (final m in visibles) (aCm(m.metros) - bajo) / math.max(1, alto - bajo)];
    final ref = deReferencia ? ' (de referencia)' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Probar otra altura', style: tema.titleMedium)),
        // Con letra grande el número de arriba queda fuera de la pantalla
        // mientras se arrastra; acá se repite (el deslizador ya lo dice).
        ExcludeSemantics(
          child: Text(
            'Altura elegida: ${formatoAltura(cm / 100)} m',
            style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _BotonPaso(
              icono: Icons.remove,
              texto: 'Bajar $pasoTexto',
              alTocar: cm - paso >= bajo ? () => alTocarPaso(cm - paso) : null,
            ),
            Expanded(
              // Un solo nodo para TalkBack, del ancho de toda la barra, con
              // nombre ("Altura del río para el mapa") además del valor.
              child: MergeSemantics(
                child: Semantics(
                  label: textoDeslizador,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 8,
                      activeTrackColor: Colores.primario,
                      // 3:1 o más contra el fondo y contra la parte llena (1.4.11).
                      inactiveTrackColor: ColoresDeslizador.pistaVacia,
                      thumbColor: Colores.primario,
                      overlayColor: Colores.primario.withValues(alpha: 0.12),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                      tickMarkShape: SliderTickMarkShape.noTickMark,
                      showValueIndicator: ShowValueIndicator.never,
                      trackShape: PistaConMarcas(fracciones: fracciones, color: Colores.tinta),
                    ),
                    child: Slider(
                      value: cm.toDouble(),
                      min: bajo.toDouble(),
                      max: alto.toDouble(),
                      divisions: math.max(1, (alto - bajo) ~/ paso),
                      semanticFormatterCallback: (v) => valorParaLector(v.round()),
                      onChangeStart: (_) => alEmpezar(),
                      onChanged: (v) {
                        final nuevo = bajo + ((v.round() - bajo) / paso).round() * paso;
                        if (nuevo != cm) alCambiar(nuevo);
                      },
                      onChangeEnd: (_) => alSoltar(),
                    ),
                  ),
                ),
              ),
            ),
            _BotonPaso(
              icono: Icons.add,
              texto: 'Subir $pasoTexto',
              alTocar: cm + paso <= alto ? () => alTocarPaso(cm + paso) : null,
            ),
          ],
        ),
        if (visibles.isNotEmpty)
          Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              for (final m in visibles)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(estiloNivel(m.nivel).icono, size: 18, color: ColoresNivel.familia(m.nivel)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Semantics(
                        label: unidadesEnPalabras(
                          'Marca de ${estiloNivel(m.nivel).nombre.toLowerCase()}: ${formatoAltura(m.metros)} m$ref',
                        ),
                        excludeSemantics: true,
                        child: Text(
                          '${estiloNivel(m.nivel).nombre}: ${formatoAltura(m.metros)} m$ref',
                          style: tema.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

/// Nombre del deslizador para TalkBack.
const textoDeslizador = 'Altura del río para el mapa';

/// Pista vacía del deslizador (antes primarioSuave: 1,15 / 1,49, no llegaba).
/// 3:1 o más contra el fondo de la app (claro 3,73 · oscuro 3,56); contra la
/// parte llena 2,8 (la separa además el pulgar). Ver docs/mapa/10-accesibilidad.md.
abstract final class ColoresDeslizador {
  static Color get pistaVacia => Colores.oscuro ? const Color(0xFF4A7590) : const Color(0xFF5E8199);
}

/// Pista redondeada con palitos en las alturas de los umbrales, debajo de la
/// barra (sin texto: el texto va en un renglón aparte para que no se pise).
class PistaConMarcas extends RoundedRectSliderTrackShape {
  final List<double> fracciones;
  final Color color;

  const PistaConMarcas({required this.fracciones, required this.color});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final pista = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final pintura = Paint()..color = color;
    for (final f in fracciones) {
      final x = pista.left + f * pista.width;
      context.canvas.drawRect(Rect.fromLTWH(x - 1, pista.bottom + 4, 2, 10), pintura);
    }
  }
}

class _BotonPaso extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback? alTocar;

  const _BotonPaso({required this.icono, required this.texto, required this.alTocar});

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: texto,
    onPressed: alTocar,
    constraints: const BoxConstraints.tightFor(width: 56, height: 56),
    icon: Icon(icono, size: 28),
  );
}

// ---------------------------------------------------------------------------
// Alturas para comparar

enum TipoAltura { hoy, pronostico, alerta, evacuacion, crecida }

/// Un botón de altura con nombre.
class AlturaComparar {
  final TipoAltura tipo;
  final String titulo;
  final String detalle;
  final double metros;
  final ReferenciaMapa? referencia;
  final bool elegido;

  /// El detalle tal como lo dice TalkBack, si difiere del escrito.
  final String? detalleVoz;

  const AlturaComparar({
    required this.tipo,
    required this.titulo,
    required this.detalle,
    required this.metros,
    this.referencia,
    this.elegido = false,
    this.detalleVoz,
  });

  /// "Nivel de alerta, 4,39 metros (de referencia)".
  String get paraLector => '$titulo, ${unidadesEnPalabras(detalleVoz ?? detalle)}';
}

/// Dos columnas si entran (ancho / letra ≥ 300 dp), si no una.
int columnasAlturas(double ancho, double escalaLetra) => ancho / escalaLetra >= 300 ? 2 : 1;

class GrillaAlturas extends StatelessWidget {
  final List<AlturaComparar> alturas;
  final ValueChanged<AlturaComparar> alTocar;

  const GrillaAlturas({super.key, required this.alturas, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, limites) {
        final columnas = columnasAlturas(limites.maxWidth, escala);
        Widget boton(AlturaComparar a) => BotonAltura(altura: a, alTocar: () => alTocar(a));
        final filas = <Widget>[];
        for (var i = 0; i < alturas.length; i += columnas) {
          final fila = alturas.skip(i).take(columnas).toList();
          filas.add(
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: columnas == 1
                  ? boton(fila.single)
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: boton(fila[0])),
                          const SizedBox(width: 8),
                          Expanded(child: fila.length > 1 ? boton(fila[1]) : const SizedBox()),
                        ],
                      ),
                    ),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filas);
      },
    );
  }
}

/// Botón de dos renglones (nombre / altura). El elegido va relleno y con
/// tilde: el estado no depende solo del color.
class BotonAltura extends StatelessWidget {
  final AlturaComparar altura;
  final VoidCallback alTocar;

  const BotonAltura({super.key, required this.altura, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final a = altura;
    final color = a.elegido ? Colores.sobrePrimario : Colores.primario;
    final hijo = Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.elegido) ...[Icon(Icons.check, size: 20, color: color), const SizedBox(width: 6)],
              Flexible(
                child: Text(a.titulo, style: tema.titleMedium?.copyWith(color: color)),
              ),
            ],
          ),
          Text(a.detalle, style: tema.bodyLarge?.copyWith(color: color, fontSize: 17)),
        ],
      ),
    );
    final estilo = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 64)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
    );
    // Un solo nodo para TalkBack: "Nivel de alerta, 4,39 metros, botón,
    // seleccionado". Sin MergeSemantics el "seleccionado" quedaba en un nodo
    // vacío aparte y TalkBack no lo decía.
    final conVoz = Semantics(label: a.paraLector, excludeSemantics: true, child: hijo);
    return MergeSemantics(
      child: Semantics(
        selected: a.elegido,
        child: a.elegido
            ? FilledButton(onPressed: alTocar, style: estilo, child: conVoz)
            : OutlinedButton(onPressed: alTocar, style: estilo, child: conVoz),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leyenda

class EntradaLeyenda {
  /// null: fila solo de texto (algo que el mapa no puede dibujar, como la
  /// zona sin validar cuando falta su archivo).
  final CustomPainter? muestra;
  final String texto;

  const EntradaLeyenda(this.muestra, this.texto);
}

/// "Qué muestra el mapa": siempre abierta. No conoce colores: recibe las
/// muestras del cartógrafo (mapa/estilo_mapa.dart).
class LeyendaMapa extends StatelessWidget {
  final List<EntradaLeyenda> entradas;

  const LeyendaMapa({super.key, required this.entradas});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Qué muestra el mapa', style: tema.titleMedium)),
        for (final e in entradas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 36,
                      height: 22,
                      child: e.muestra == null
                          ? Icon(Icons.info_outline, size: 22, color: Colores.tintaSecundaria)
                          : CustomPaint(painter: e.muestra),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(e.texto, style: tema.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pie

class PieMapa extends StatelessWidget {
  final IndiceMapa indice;

  const PieMapa({super.key, required this.indice});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final apoyo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    final generado = indice.generado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(textoTituloAproximado, style: tema.titleMedium)),
        const SizedBox(height: 4),
        Text(textoMapaAproximado, style: tema.bodyLarge),
        const SizedBox(height: 12),
        Text(textoDatosMapa, style: apoyo),
        if (generado != null) Text('Mapa armado el ${formatoDia(enHoraUruguay(generado))}.', style: apoyo),
        const SizedBox(height: 4),
        Wrap(
          spacing: 20,
          children: [
            TextButton(onPressed: () => mostrarFuentes(context, indice), child: const Text('Ver fuentes')),
            TextButton(onPressed: () => mostrarComoSeUsa(context), child: const Text('Cómo se usa')),
          ],
        ),
      ],
    );
  }
}

/// Recuadro único del dato de hoy (reusa el ámbar de la app).
class RecuadroHoyMapa extends StatelessWidget {
  final Aviso aviso;

  const RecuadroHoyMapa({super.key, required this.aviso});

  @override
  Widget build(BuildContext context) => Recuadro(icono: aviso.icono, texto: aviso.texto);
}

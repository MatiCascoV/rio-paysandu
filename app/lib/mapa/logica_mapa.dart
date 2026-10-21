/// Qué capa se pinta para una altura (docs/mapa/05-contrato.md, "Cómo elige
/// la app qué capa pintar"). Todo en centímetros enteros.
library;

import 'modelos_mapa.dart';

/// Redondea hacia arriba al siguiente múltiplo de [pasoCm]: 5,63 m → 5,70 m.
/// Del lado de la prudencia: mejor mostrar un poco más de agua.
int redondearArriba(double metros, {int pasoCm = 10}) {
  final cm = aCm(metros);
  final resto = cm % pasoCm;
  return resto == 0 ? cm : cm - resto + pasoCm;
}

enum SituacionAgua {
  /// Por debajo de la capa más baja (`min_m`). El agua no pasa de la zona
  /// baja de la costa, que se dibuja igual (contrato v1.1 §3). Nunca se dice
  /// "en su cauce": esa capa ya moja islas y bañados.
  debajoDelMinimo,

  /// Hay una capa para esa altura.
  enRango,

  /// Por encima de la más alta: se pinta la máxima y se avisa.
  sobreMaximo,
}

/// Qué pintar para una altura elegida.
class EleccionAgua {
  final int alturaCm;
  final SituacionAgua situacion;

  /// Capa a pintar como "agua", o null por debajo del mínimo.
  final int? capaCm;

  /// Capa del margen ("puede llegar un poco más"). Siempre hay (contrato
  /// v1.1 §4, condición para publicar): de [capaCm] hasta la capa de
  /// altura + margen, recortada a las capas que existen. En el máximo o por
  /// encima coincide con la capa máxima.
  final int margenCm;

  /// Zona baja de la costa: la capa de `min_m`, que se dibuja siempre con su
  /// propio estilo (contrato v1.1 §3).
  final int zonaBajaCm;

  /// true si altura + margen pasa de la capa más alta: la franja de puntos
  /// quedó recortada en `max_m` (más angosta que el margen, o de ancho 0 en
  /// el máximo) y el agua puede pasar los puntos. La pantalla lo avisa.
  final bool margenRecortado;

  const EleccionAgua({
    required this.alturaCm,
    required this.situacion,
    required this.margenCm,
    required this.zonaBajaCm,
    this.capaCm,
    this.margenRecortado = false,
  });

  /// El agua dibujada no pasa de la zona baja (altura ≤ `min_m`). Con 3,90 y
  /// con 4,00 se dice lo mismo: así no hay salto de texto en el mínimo.
  bool get noPasaDeLaZonaBaja => alturaCm <= zonaBajaCm;
}

/// [alturaCm] ya redondeada al paso del índice.
EleccionAgua elegirAgua(int alturaCm, IndiceMapa indice) {
  final situacion = alturaCm < indice.minCm
      ? SituacionAgua.debajoDelMinimo
      : alturaCm > indice.maxCm
      ? SituacionAgua.sobreMaximo
      : SituacionAgua.enRango;
  final capa = switch (situacion) {
    SituacionAgua.debajoDelMinimo => null,
    SituacionAgua.enRango => alturaCm,
    SituacionAgua.sobreMaximo => indice.maxCm,
  };
  // El margen se redondea también hacia arriba y queda dentro de las capas
  // que existen: nunca debajo de la zona baja ni encima del máximo.
  final conMargen = alturaCm + indice.margenCm;
  final resto = (conMargen - indice.minCm) % indice.pasoCm;
  final margen = (resto == 0 ? conMargen : conMargen - resto + indice.pasoCm).clamp(indice.minCm, indice.maxCm);
  return EleccionAgua(
    alturaCm: alturaCm,
    situacion: situacion,
    capaCm: capa,
    margenCm: margen,
    zonaBajaCm: indice.minCm,
    margenRecortado: conMargen > indice.maxCm,
  );
}

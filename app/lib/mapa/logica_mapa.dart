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
  /// Por debajo de la capa más baja: el agua queda en su cauce.
  enCauce,

  /// Hay una capa para esa altura.
  enRango,

  /// Por encima de la más alta: se pinta la máxima y se avisa.
  sobreMaximo,
}

/// Qué pintar para una altura elegida.
class EleccionAgua {
  final int alturaCm;
  final SituacionAgua situacion;

  /// Capa a pintar como "agua", o null si queda en el cauce.
  final int? capaCm;

  /// Capa del margen ("puede llegar un poco más"), o null si no hay o
  /// coincide con [capaCm].
  final int? margenCm;

  const EleccionAgua({required this.alturaCm, required this.situacion, this.capaCm, this.margenCm});
}

/// [alturaCm] ya redondeada al paso del índice.
EleccionAgua elegirAgua(int alturaCm, IndiceMapa indice) {
  final situacion = alturaCm < indice.minCm
      ? SituacionAgua.enCauce
      : alturaCm > indice.maxCm
      ? SituacionAgua.sobreMaximo
      : SituacionAgua.enRango;
  final capa = switch (situacion) {
    SituacionAgua.enCauce => null,
    SituacionAgua.enRango => alturaCm,
    SituacionAgua.sobreMaximo => indice.maxCm,
  };
  // El margen se redondea también hacia arriba y no pasa del máximo.
  final conMargen = alturaCm + indice.margenCm;
  final resto = (conMargen - indice.minCm) % indice.pasoCm;
  var margen = resto == 0 ? conMargen : conMargen - resto + indice.pasoCm;
  if (margen > indice.maxCm) margen = indice.maxCm;
  final hayMargen = indice.margenCm > 0 && margen >= indice.minCm && margen != capa;
  return EleccionAgua(alturaCm: alturaCm, situacion: situacion, capaCm: capa, margenCm: hayMargen ? margen : null);
}

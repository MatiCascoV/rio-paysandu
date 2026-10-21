import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rio_paysandu/avisos.dart';
import 'package:rio_paysandu/pantallas/olas.dart';

/// Corre antes de cada archivo de pruebas. Las olas de Inicio se mueven sin
/// fin y pumpAndSettle esperaría para siempre: en las pruebas quedan quietas,
/// salvo en las que prueban justamente el movimiento (que lo prenden y apagan).
Future<void> testExecutable(FutureOr<void> Function() pruebas) async {
  OlasNivel.animar = false;
  // Las revisiones de avisos van de a una (ver decidirAvisos); cada prueba empieza sin ninguna en curso.
  setUp(reiniciarTurnoDeAvisos);
  await pruebas();
}

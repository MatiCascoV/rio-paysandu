/// Pantalla de primer arranque: se muestra una sola vez, en una instalación
/// nueva, antes de pedir ningún permiso ni suscribir ningún tema. La persona
/// elige si quiere avisos de crecida; después lo puede cambiar en la pestaña Avisos.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../avisos.dart';
import '../modelos.dart';
import '../tema.dart';
import 'ajustes.dart';
import 'comunes.dart';

/// Lo que explica la pantalla sobre Firebase (también está en Avisos, con las mismas palabras).
const textoIdentificadorFirebase =
    'Firebase, el servicio de Google que entrega los avisos, le asigna a tu '
    'instalación un identificador anónimo desde que se abre la app, aunque no actives nada. '
    'Apagar los avisos quita las suscripciones, pero el identificador sigue hasta que desinstales la app. '
    'No hay cuentas ni registro.';

class PantallaPrimerArranque extends StatefulWidget {
  final SharedPreferences prefs;
  final ControlAvisos control;

  /// Se llama cuando la persona terminó de elegir (activando o no).
  final VoidCallback alTerminar;

  const PantallaPrimerArranque({super.key, required this.prefs, required this.control, required this.alTerminar});

  @override
  State<PantallaPrimerArranque> createState() => _PantallaPrimerArranqueState();
}

class _PantallaPrimerArranqueState extends State<PantallaPrimerArranque> {
  bool _trabajando = false;
  bool _sinPermiso = false;

  /// Prende el urgente (desde alerta) y el resumen, y recién ahí pide el
  /// permiso y suscribe los temas. Sin permiso, queda todo apagado.
  Future<void> _activar() async {
    if (_trabajando) return;
    setState(() => _trabajando = true);
    final prefs = widget.prefs;
    bool permitido;
    try {
      permitido = await widget.control.pedirPermiso();
    } catch (_) {
      permitido = false;
    }
    if (!mounted) return;
    if (!permitido) {
      // Nada prendido que no vaya a llegar. La elección ya está hecha: se puede seguir.
      await prefs.setString(clavePrimerArranque, primerArranqueHecho);
      setState(() {
        _trabajando = false;
        _sinPermiso = true;
      });
      return;
    }
    await migrarPreferencias(prefs);
    await prefs.setBool(claveUrgente, true);
    await prefs.setString(claveUrgenteDesde, nivelATexto(Nivel.alerta));
    await prefs.setBool(claveResumen, true);
    await prefs.setString(clavePrimerArranque, primerArranqueHecho);
    try {
      await widget.control.aplicar(prefs);
    } catch (_) {
      // Sin la revisión de respaldo igual llegan los push; Avisos lo reintenta al cambiar algo.
    }
    // Los temas se acomodan sin trabar nada: sin conexión quedan pendientes y
    // se reintenta al abrir la app (ver Push.iniciar).
    widget.control.sincronizarTemas(prefs).catchError((_) => false);
    if (mounted) widget.alTerminar();
  }

  /// Todo apagado y ningún tema: no se suscribe a nada.
  Future<void> _ahoraNo() async {
    if (_trabajando) return;
    final prefs = widget.prefs;
    await prefs.setString(clavePrimerArranque, primerArranqueHecho);
    if (mounted) widget.alTerminar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final apoyo = tema.bodyLarge?.copyWith(color: Colores.tintaSecundaria);
    // Botones grandes y con la letra del tema (crece con el agrandado de letra del teléfono).
    final estiloBoton = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60)),
      textStyle: WidgetStatePropertyAll(tema.titleMedium),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            // Los botones quedan fijos abajo: se alcanzan siempre, aunque el texto
            // sea largo (pantalla chica, letra al 200 %) y haya que desplazar.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.notifications_active, size: 48, color: Colores.primario),
                        const SizedBox(height: 16),
                        Semantics(header: true, child: Text('¿Querés avisos de crecida?', style: tema.headlineSmall)),
                        const SizedBox(height: 16),
                        Text(
                          'Te avisamos si el río sube a alerta o evacuación, y un resumen cuando el nivel esté alto.',
                          style: tema.bodyLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'App comunitaria, no oficial: la alerta oficial la dan el Sinae y el Cecoed.',
                          style: tema.bodyLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Si activás, Android te va a pedir permiso para mostrar notificaciones.',
                          style: tema.bodyLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(textoIdentificadorFirebase, style: apoyo),
                        const SizedBox(height: 12),
                        Text('Lo podés cambiar cuando quieras en la pestaña Avisos.', style: apoyo),
                        const EnlacePrivacidad(),
                        if (_sinPermiso) ...[
                          const SizedBox(height: 16),
                          const Recuadro(
                            icono: Icons.notifications_off,
                            texto:
                                'No diste permiso para las notificaciones, así que los avisos quedaron apagados. '
                                'Los podés activar después en la pestaña Avisos.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_sinPermiso)
                        FilledButton(style: estiloBoton, onPressed: widget.alTerminar, child: const Text('Seguir'))
                      else ...[
                        FilledButton(
                          style: estiloBoton,
                          onPressed: _trabajando ? null : _activar,
                          child: const Text('Activar avisos'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          style: estiloBoton,
                          onPressed: _trabajando ? null : _ahoraNo,
                          child: const Text('Ahora no'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

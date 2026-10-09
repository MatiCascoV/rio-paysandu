import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../datos.dart';
import '../modelos.dart';
import '../notificaciones.dart';
import '../textos.dart';
import 'comunes.dart';

/// Pestaña "Avisos": activar las notificaciones y elegir desde qué nivel avisar.
class PantallaAjustes extends StatefulWidget {
  final SharedPreferences prefs;
  final Datos? datos;
  final Config? config;
  final VoidCallback? alCambiar;

  const PantallaAjustes({super.key, required this.prefs, this.datos, this.config, this.alCambiar});

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> {
  bool _sinPermiso = false;

  bool get _activos => widget.prefs.getBool(claveActivos) ?? false;
  Nivel get _desde => nivelDesdeTexto(widget.prefs.getString(claveDesde) ?? 'alerta');

  Future<void> _cambiarActivos(bool valor) async {
    final ok = await Notificaciones.activar(valor, widget.prefs);
    if (!mounted) return;
    setState(() => _sinPermiso = valor && !ok);
    if (ok) widget.alCambiar?.call();
  }

  Future<void> _cambiarDesde(Nivel? nivel) async {
    if (nivel == null) return;
    await widget.prefs.setString(claveDesde, nivelATexto(nivel));
    if (mounted) setState(() {});
  }

  /// "Ahora el río está en ALERTA (5,95 m). El próximo aviso llega si…"
  String? _estadoActual(Umbrales? u, Nivel elegido) {
    final actual = widget.datos?.actual;
    final altura = actual?.altura;
    if (actual == null || altura == null) return null;
    final nivel = actual.nivelVigente(DateTime.now(), widget.config?.horasSinDato ?? 48);
    if (nivel == Nivel.sinDato) return null;
    final ahora = 'Ahora el río está en nivel ${estiloNivel(nivel).nombre.toUpperCase()} (${formatoAltura(altura.valorM)} m).';
    final evacuacion = u?.evacuacionM == null ? '' : ' (${formatoAltura(u!.evacuacionM!)} m)';
    final proximo = switch (nivel) {
      Nivel.evacuacion => 'El próximo aviso llega cuando baje de ese nivel.',
      Nivel.alerta => elegido == Nivel.evacuacion
          ? 'El próximo aviso llega si pasa a evacuación$evacuacion.'
          : 'El próximo aviso llega si pasa a evacuación$evacuacion o si baja de alerta.',
      _ => 'El próximo aviso llega si pasa a nivel de ${estiloNivel(elegido).nombre.toLowerCase()}.',
    };
    return '$ahora $proximo';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final u = widget.datos?.umbrales;
    // Solo se ofrecen los niveles que tienen un valor definido.
    final opciones = [
      if (u == null || u.atencionM != null) Nivel.atencion,
      Nivel.alerta,
      Nivel.evacuacion,
    ];
    final elegido = opciones.contains(_desde) ? _desde : Nivel.alerta;
    final estado = _activos ? _estadoActual(u, elegido) : null;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SwitchListTile(
          title: Text('Recibir avisos', style: tema.titleLarge),
          subtitle: Text(
            'El teléfono te avisa cuando el río cambia de nivel. No avisa cada vez que sube unos centímetros.',
            style: tema.bodyLarge,
          ),
          value: _activos,
          onChanged: _cambiarActivos,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              if (_sinPermiso)
                Recuadro(
                  icono: Icons.notifications_off,
                  texto: kIsWeb
                      ? 'Los avisos solo funcionan en la app para Android.'
                      : 'Para recibir avisos tenés que permitir las notificaciones de esta app en los ajustes del teléfono.',
                ),
              if (estado != null) Recuadro(icono: Icons.notifications_active, fondo: const Color(0xFFE3F2FD), texto: 'Avisos prendidos. $estado'),
              const Recuadro(
                icono: Icons.schedule,
                texto: 'El aviso puede llegar tarde: algunos teléfonos lo demoran para ahorrar batería. '
                    'Si el río está creciendo, abrí la app seguido y seguí la información del Cecoed.',
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Semantics(header: true, child: Text('Avisarme desde el nivel', style: tema.titleLarge)),
        ),
        if (!_activos)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Primero prendé "Recibir avisos".', style: tema.bodyLarge),
          ),
        RadioGroup<Nivel>(
          groupValue: elegido,
          onChanged: _cambiarDesde,
          child: Column(
            children: [
              for (final n in opciones)
                RadioListTile<Nivel>(
                  value: n,
                  enabled: _activos,
                  title: Text(estiloNivel(n).nombre, style: tema.titleMedium),
                  subtitle: u?.de(n) == null ? null : Text('${formatoAltura(u!.de(n)!)} m o más', style: tema.bodyLarge),
                ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'La app revisa el nivel cuando la abrís y, si el teléfono lo permite, cada tanto aunque esté cerrada.\n\n'
            'Los datos son de CARU, la Comisión Administradora del Río Uruguay. '
            'Esta app no pide registro, no tiene publicidad y no recolecta datos personales.',
            style: tema.bodyLarge,
          ),
        ),
      ],
    );
  }
}

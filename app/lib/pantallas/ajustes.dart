import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos.dart';
import '../notificaciones.dart';
import '../textos.dart';

class PantallaAjustes extends StatefulWidget {
  final SharedPreferences prefs;
  final Umbrales? umbrales;

  const PantallaAjustes({super.key, required this.prefs, required this.umbrales});

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> {
  bool get _activos => widget.prefs.getBool(claveActivos) ?? false;
  Nivel get _desde => nivelDesdeTexto(widget.prefs.getString(claveDesde) ?? 'alerta');

  Future<void> _cambiarActivos(bool valor) async {
    final mensajes = ScaffoldMessenger.of(context);
    final ok = await Notificaciones.activar(valor, widget.prefs);
    if (!ok) {
      mensajes.showSnackBar(SnackBar(
        content: Text(kIsWeb
            ? 'Los avisos solo funcionan en la app para Android.'
            : 'Para recibir avisos tenés que permitir las notificaciones de esta app en los ajustes del teléfono.'),
      ));
    }
    if (mounted) setState(() {});
  }

  Future<void> _cambiarDesde(Nivel? nivel) async {
    if (nivel == null) return;
    await widget.prefs.setString(claveDesde, nivelATexto(nivel));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final u = widget.umbrales;
    // Solo se ofrecen los niveles que tienen un valor definido.
    final opciones = [
      if (u == null || u.atencionM != null) Nivel.atencion,
      Nivel.alerta,
      Nivel.evacuacion,
    ];
    final elegido = opciones.contains(_desde) ? _desde : Nivel.alerta;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SwitchListTile(
          title: Text('Recibir avisos', style: tema.titleLarge),
          subtitle: Text('El teléfono te avisa cuando el río cambia de nivel.', style: tema.bodyLarge),
          value: _activos,
          onChanged: _cambiarActivos,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Semantics(header: true, child: Text('Avisarme desde el nivel', style: tema.titleLarge)),
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
            'La app revisa el nivel cuando la abrís y, si el teléfono lo permite, cada tanto aunque esté '
            'cerrada. Algunos teléfonos demoran esos avisos para ahorrar batería, así que pueden llegar tarde.\n\n'
            'Los datos son de la Comisión Administradora del Río Uruguay (CARU). '
            'Esta app no pide registro, no tiene publicidad y no recolecta datos personales.',
            style: tema.bodyLarge,
          ),
        ),
      ],
    );
  }
}

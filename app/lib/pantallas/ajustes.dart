import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../avisos.dart';
import '../datos.dart';
import '../modelos.dart';
import '../notificaciones.dart';
import '../push.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

/// Lo que la pestaña necesita del teléfono. En las pruebas se cambia por uno falso.
abstract class ControlAvisos {
  /// ¿Puede la app mostrar notificaciones? null si no se sabe.
  Future<bool?> permitidas();

  /// Pide el permiso de notificaciones; false si no se dio.
  Future<bool> pedirPermiso();

  /// Programa o cancela la revisión de respaldo según las preferencias. Lanza si no se puede.
  Future<void> aplicar(SharedPreferences prefs);

  /// Suscribe y desuscribe los temas de push; false si quedó pendiente.
  Future<bool> sincronizarTemas(SharedPreferences prefs);

  /// false si este teléfono no puede recibir push (sin servicios de Google).
  bool get pushDisponible;
}

class ControlAvisosDelTelefono implements ControlAvisos {
  const ControlAvisosDelTelefono();

  @override
  Future<bool?> permitidas() => Notificaciones.permitidas();

  @override
  Future<bool> pedirPermiso() => Notificaciones.pedirPermiso();

  @override
  Future<void> aplicar(SharedPreferences prefs) => Notificaciones.aplicar(prefs);

  @override
  Future<bool> sincronizarTemas(SharedPreferences prefs) => Push.sincronizar(prefs);

  @override
  bool get pushDisponible => Push.disponible;
}

/// Pestaña "Avisos": el aviso urgente (desde alerta o solo evacuación) y el resumen del día.
class PantallaAjustes extends StatefulWidget {
  final SharedPreferences prefs;
  final Datos? datos;
  final Config? config;
  final VoidCallback? alCambiar;
  final ControlAvisos control;

  const PantallaAjustes({
    super.key,
    required this.prefs,
    this.datos,
    this.config,
    this.alCambiar,
    this.control = const ControlAvisosDelTelefono(),
  });

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> with WidgetsBindingObserver {
  /// null mientras no se sabe (o si el teléfono no lo dice).
  bool? _permitidas;
  bool _sinPermiso = false;
  bool _fallo = false;
  bool _sincronizando = false;

  PreferenciasAvisos get _p => PreferenciasAvisos.leer(widget.prefs);

  /// Nunca se muestra prendido algo que no va a llegar: sin permiso, apagado.
  bool get _bloqueadas => _permitidas == false;
  bool get _urgente => _p.urgente && !_bloqueadas;
  bool get _resumen => _p.resumen && !_bloqueadas;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _revisarPermiso();
  }

  @override
  void didUpdateWidget(PantallaAjustes anterior) {
    super.didUpdateWidget(anterior);
    _revisarPermiso(); // por ejemplo, después del pedido de permiso al abrir la app
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del teléfono, el permiso pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _revisarPermiso();
  }

  Future<void> _revisarPermiso() async {
    bool? permitidas;
    try {
      permitidas = await widget.control.permitidas();
    } catch (_) {}
    if (!mounted || permitidas == _permitidas) return;
    setState(() {
      _permitidas = permitidas;
      if (permitidas == true) _sinPermiso = false;
    });
  }

  /// Prende o apaga un tipo de aviso ([clave] es la de urgente o la de resumen).
  Future<void> _cambiar(String clave, bool valor) async {
    final prefs = widget.prefs;
    if (valor) {
      bool permitido;
      try {
        permitido = await widget.control.pedirPermiso();
      } catch (_) {
        permitido = false;
      }
      if (!mounted) return;
      if (!permitido) {
        setState(() {
          _sinPermiso = true;
          _permitidas = false;
        });
        return;
      }
      setState(() {
        _permitidas = true;
        _sinPermiso = false;
      });
    }
    final antes = prefs.getBool(clave);
    await migrarPreferencias(prefs);
    await prefs.setBool(clave, valor);
    try {
      await widget.control.aplicar(prefs);
      if (mounted) setState(() => _fallo = false);
    } catch (_) {
      if (valor) {
        // Si la revisión de respaldo no se pudo programar, el interruptor vuelve a como estaba.
        if (antes == null) {
          await prefs.remove(clave);
        } else {
          await prefs.setBool(clave, antes);
        }
        if (mounted) setState(() => _fallo = true);
        return;
      }
      // Al apagar no hace falta: la revisión mira las preferencias y no avisa.
    }
    if (mounted) setState(() {});
    widget.alCambiar?.call();
    await _sincronizar();
  }

  Future<void> _cambiarDesde(Nivel? nivel) async {
    if (nivel == null) return;
    await migrarPreferencias(widget.prefs);
    await widget.prefs.setString(claveUrgenteDesde, nivelATexto(nivel));
    if (mounted) setState(() {});
    await _sincronizar();
  }

  /// Los temas se acomodan sin trabar la pantalla: si no hay conexión, queda
  /// pendiente y se reintenta la próxima vez que se abra la app.
  Future<void> _sincronizar() async {
    if (mounted) setState(() => _sincronizando = true);
    try {
      await widget.control.sincronizarTemas(widget.prefs);
    } catch (_) {}
    if (mounted) setState(() => _sincronizando = false);
  }

  /// "Ahora el río está en nivel ATENCIÓN (4,10 m). El próximo aviso urgente llega si…"
  String? _estadoActual(Umbrales? u, Nivel desde) {
    final actual = widget.datos?.actual;
    final altura = actual?.altura;
    if (actual == null || altura == null) return null;
    final nivel = actual.nivelVigente(DateTime.now(), widget.config?.horasSinDato ?? 48);
    if (nivel == Nivel.sinDato) return null;
    final ahora =
        'Ahora el río está en nivel ${estiloNivel(nivel).nombre.toUpperCase()} (${formatoAltura(altura.valorM)} m).';
    String metros(double? m) => m == null ? '' : ' (${formatoAltura(m)} m)';
    final proximo = switch (nivel) {
      Nivel.evacuacion => 'Si baja y vuelve a subir, te avisa de nuevo.',
      Nivel.alerta => 'El próximo aviso urgente llega si sube a evacuación${metros(u?.evacuacionM)}.',
      _ => desde == Nivel.evacuacion
          ? 'El próximo aviso urgente llega si sube a evacuación${metros(u?.evacuacionM)}.'
          : 'El próximo aviso urgente llega si sube a alerta${metros(u?.alertaM)}.',
    };
    return '$ahora $proximo';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final apoyo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    final u = widget.datos?.umbrales;
    final p = _p;
    final urgente = _urgente;
    final estado = urgente ? _estadoActual(u, p.desde) : null;
    String metros(double? m) => m == null ? '' : ' (${formatoAltura(m)} m)';
    final colorOpcion = urgente ? Colores.tinta : Colores.bordeControl;
    final pendiente = (urgente || _resumen) && !_sincronizando && !temasAlDia(widget.prefs);

    Widget opcion(Nivel n, String titulo, String detalle) => RadioListTile<Nivel>(
          value: n,
          enabled: urgente,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // El ícono del nivel acompaña al nombre (no depende del color).
          secondary: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(estiloNivel(n).icono, color: urgente ? estiloNivel(n).oscuro : Colores.bordeControl),
          ),
          title: Text(titulo,
              style: (n == p.desde && urgente ? tema.titleMedium : tema.bodyLarge)?.copyWith(color: colorOpcion)),
          subtitle: Text(detalle,
              style: tema.bodyMedium?.copyWith(color: urgente ? Colores.tintaSecundaria : Colores.bordeControl)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_sinPermiso || (_bloqueadas && p.algunoPrendido)) ...[
          Recuadro(
            icono: Icons.notifications_off,
            texto: kIsWeb
                ? 'Los avisos solo funcionan en la app para Android.'
                : 'Las notificaciones de esta app están bloqueadas, así que no te llega ningún aviso. '
                    'Para arreglarlo, entrá a los ajustes del teléfono, buscá Mi Río UY en Aplicaciones, '
                    'tocá Notificaciones y permitilas.',
          ),
          const SizedBox(height: 12),
        ],
        if (_fallo) ...[
          const Recuadro(
            icono: Icons.error_outline,
            texto: 'No se pudieron cambiar los avisos en este teléfono. Probá de nuevo; si sigue igual, '
                'cerrá y volvé a abrir la app.',
          ),
          const SizedBox(height: 12),
        ],

        // ----- Aviso urgente -----
        Semantics(header: true, child: Text('Aviso urgente', style: tema.titleLarge)),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                title: Text('Recibir el aviso urgente', style: tema.titleMedium),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Te avisa apenas el río sube al nivel que elijas abajo. No avisa cuando baja.', style: tema.bodyLarge),
                ),
                value: urgente,
                onChanged: kIsWeb ? null : (v) => _cambiar(claveUrgente, v),
              ),
              Divider(indent: 16, endIndent: 16, color: Colores.bordeSuave),
              RadioGroup<Nivel>(
                groupValue: p.desde,
                onChanged: _cambiarDesde,
                child: Column(
                  children: [
                    opcion(Nivel.alerta, 'Desde alerta',
                        'Avisa al subir a alerta${metros(u?.alertaM)} y a evacuación${metros(u?.evacuacionM)}.'),
                    Divider(indent: 16, endIndent: 16, color: Colores.bordeSuave),
                    opcion(Nivel.evacuacion, 'Solo evacuación', 'Avisa solo al subir a evacuación${metros(u?.evacuacionM)}.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (estado != null) ...[const SizedBox(height: 12), Text(estado, style: tema.bodyLarge)],

        // ----- Resumen del día -----
        const SizedBox(height: 32),
        Semantics(header: true, child: Text('Resumen del día', style: tema.titleLarge)),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            title: Text('Recibir el resumen', style: tema.titleMedium),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Una notificación por día, a la mañana, con la altura del río y cuánto subió o bajó. '
                'Solo sale cuando el río está en atención o más: con el río normal no llega nada.',
                style: tema.bodyLarge,
              ),
            ),
            value: _resumen,
            onChanged: kIsWeb ? null : (v) => _cambiar(claveResumen, v),
          ),
        ),

        const SizedBox(height: 24),
        if (pendiente) ...[
          Text(
            widget.control.pushDisponible
                ? 'Los avisos al instante se terminan de activar cuando el teléfono tenga conexión. '
                    'Mientras tanto, la app revisa el río cada tanto.'
                : 'Este teléfono no puede recibir avisos al instante. La app revisa el río cada tanto, '
                    'así que los avisos pueden llegar más tarde.',
            style: tema.bodyMedium,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Estos avisos no reemplazan la alerta oficial: la dan el Sinae y el Cecoed.',
          style: tema.bodyMedium,
        ),
        const SizedBox(height: 8),
        Theme(
          // Sin las líneas que el plegable dibuja arriba y abajo.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('¿No te llegan los avisos?', style: tema.titleMedium),
            children: [
              Text(
                'En los Xiaomi, Redmi y POCO:\n'
                '1. Mantené apretado el ícono de Mi Río UY y tocá «Información de la app».\n'
                '2. Prendé «Inicio automático».\n'
                '3. En «Ahorro de batería», elegí «Sin restricciones».\n\n'
                'En otros teléfonos: en Ajustes, Aplicaciones, Mi Río UY, revisá que las notificaciones '
                'estén permitidas y que la batería esté «Sin restricciones» (o «No optimizar»).\n\n'
                'Con el ahorro de batería prendido, algunos avisos pueden demorarse.',
                style: tema.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Los avisos llegan por Firebase Cloud Messaging, el servicio de Google para notificaciones, '
          'sin cuenta ni registro. Además, la app revisa el nivel cuando la abrís y, si el teléfono lo '
          'permite, cada tanto aunque esté cerrada.\n\n'
          'Las alturas del río son de CARU; las crecidas anteriores, de Dinagua, y el mapa, de OpenStreetMap. '
          'Esta app no pide registro ni tiene publicidad. Para los avisos, Firebase le asigna a tu instalación '
          'un identificador anónimo; no recibimos tu nombre, tu ubicación ni tus contactos.',
          style: apoyo,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

/// Pantalla principal. Los bloques van siempre en el mismo orden; según el
/// estado (nivel, dato viejo, sin conexión…) algunos aparecen y otros no.
class PantallaInicio extends StatelessWidget {
  final Datos? datos;
  final Config config;
  final Future<void> Function() alActualizar;

  /// Si los avisos están apagados se invita a prenderlos.
  final bool avisosActivos;
  final VoidCallback? alPedirAvisos;
  final VoidCallback? alVerQueHacer;

  /// Solo para pruebas: permite fijar la hora actual.
  final DateTime? ahora;

  const PantallaInicio({
    super.key,
    required this.datos,
    required this.config,
    required this.alActualizar,
    this.avisosActivos = true,
    this.alPedirAvisos,
    this.alVerQueHacer,
    this.ahora,
  });

  @override
  Widget build(BuildContext context) {
    final datos = this.datos;
    if (datos == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando el nivel del río…', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: alActualizar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _contenido(context, datos, ahora ?? DateTime.now()),
      ),
    );
  }

  List<Widget> _contenido(BuildContext context, Datos datos, DateTime ahora) {
    final tema = Theme.of(context).textTheme;
    final secundario = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    final actual = datos.actual;
    final altura = actual?.altura;
    final nivel = actual?.nivelVigente(ahora, config.horasSinDato) ?? Nivel.sinDato;
    final estilo = estiloNivel(nivel);

    final sinConexion = datos.sinConexion
        ? Recuadro(
            icono: Icons.wifi_off,
            tipo: TipoRecuadro.sinConexion,
            texto: altura == null
                ? 'No hay conexión a internet.'
                : 'No hay conexión a internet. Se muestra el último dato guardado en este teléfono.',
          )
        : null;
    final botonQueHacer = alVerQueHacer == null
        ? null
        : OutlinedButton.icon(
            onPressed: alVerQueHacer,
            icon: const Icon(Icons.health_and_safety),
            label: const Text('Ver qué hacer'),
          );

    // ----- Sin ninguna altura para mostrar -----
    if (actual == null || altura == null) {
      return [
        ?sinConexion,
        _TarjetaEstado(estilo: estilo, descripcion: descripcionNivel(Nivel.sinDato, null)),
        const SizedBox(height: 16),
        Text(
          datos.sinConexion
              ? 'Conectate a internet y tocá "Reintentar".'
              : 'Probá de nuevo en unos minutos. Si hay personas en peligro, llamá al 911.',
          style: tema.bodyLarge,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: alActualizar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        if (botonQueHacer != null) ...[const SizedBox(height: 12), botonQueHacer],
        const SizedBox(height: 24),
        const AvisoOficial(),
      ];
    }

    final horas = ahora.difference(altura.fecha).inMinutes / 60;
    final viejo = horas > config.horasAvisoDatoViejo;
    final cuando = formatoFecha(altura.fecha, ahora);
    final pronostico = actual.pronostico;
    final esEstacion = (altura.fuente ?? '').contains('estación');
    final prefectura = actual.prefectura;
    final umbrales = datos.umbrales;
    final hayNivel = nivel != Nivel.sinDato;
    final conEscala = hayNivel && umbrales != null && EscalaNiveles.marcas(umbrales).isNotEmpty;
    final esGrave = nivel == Nivel.alerta || nivel == Nivel.evacuacion;
    const notaPuerto = 'Altura medida en el puerto de Paysandú. No es la altura del agua en tu calle.';
    // El dato pierde protagonismo cuando ya no se puede tomar como actual.
    final colorDato = viejo ? Colores.tintaSecundaria : Colores.tinta;

    return [
      ?sinConexion,

      // ----- Tarjeta de estado: nivel + altura + fecha y fuente -----
      _TarjetaEstado(
        estilo: estilo,
        descripcion: descripcionNivel(nivel, umbrales, altura.valorM),
        accion: esGrave ? botonQueHacer : null,
        // Si el dato es viejo se dice antes del número, para que no se lea como actual.
        aviso: viejo
            ? Recuadro(
                integrado: true,
                icono: Icons.schedule,
                texto: 'Este dato es de $cuando. Después no llegó información nueva: '
                    '${horas > config.horasSinDato ? 'no se puede saber el nivel actual del río.' : 'el río puede estar distinto ahora.'} '
                    'Guiate por los avisos del Cecoed.',
              )
            : null,
        lectura: [
          if (viejo || datos.sinConexion) Text('Último dato', style: tema.titleSmall?.copyWith(color: colorDato)),
          // Altura: el número grande. No crece con la letra del sistema (ya es enorme).
          Semantics(
            label: 'Altura del río: ${formatoAltura(altura.valorM)} metros',
            excludeSemantics: true,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    text: formatoAltura(altura.valorM),
                    style: TextStyle(
                      fontSize: 88,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -1,
                      color: colorDato,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    children: const [
                      TextSpan(text: ' m', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w600, letterSpacing: 0)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Tendencia: flecha y texto. Siempre en azul: no usa colores de nivel.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: viejo ? Colores.tintaSecundaria : Colores.primario, shape: BoxShape.circle),
                child: Icon(iconoTendencia(altura), size: 22, color: viejo ? Colores.superficie : Colores.sobrePrimario),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(textoTendencia(altura, pasado: viejo), style: tema.headlineSmall?.copyWith(color: colorDato)),
              ),
            ],
          ),
          if (!conEscala) ...[const SizedBox(height: 12), Text(notaPuerto, style: secundario, textAlign: TextAlign.center)],
        ],
        // Fecha, hora y fuente: toda altura mostrada las lleva, siempre a la vista.
        pie: [
          _FilaDato(icono: Icons.schedule, child: Text('Medido: $cuando', style: tema.titleMedium)),
          const SizedBox(height: 4),
          _FilaDato(icono: Icons.sensors, child: Text('Fuente: ${altura.fuente ?? 'CARU'}', style: secundario)),
        ],
      ),
      const SizedBox(height: 16),

      for (final aviso in actual.avisos)
        // Con el aviso de dato viejo ya a la vista, no se repite lo mismo.
        if (textoAviso(aviso) != null &&
            !(viejo && (aviso == 'dato_desactualizado' || aviso == 'fuente_no_disponible')))
          Recuadro(icono: Icons.warning_amber, texto: textoAviso(aviso)!),

      // ----- Dónde está el río respecto de los niveles -----
      if (conEscala) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EscalaNiveles(
                  alturaM: altura.valorM,
                  umbrales: umbrales,
                  descripcion: descripcionEscala(altura.valorM, cuando, viejo, umbrales),
                ),
                const SizedBox(height: 12),
                Text(notaPuerto, style: secundario),
                if (!umbrales.validado) ...[
                  const SizedBox(height: 4),
                  Text('Niveles de referencia: el Cecoed todavía los está revisando.', style: secundario),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],

      if (pronostico != null && pronostico.vigente && pronostico.alturaEsperadaM != null) ...[
        _TarjetaPronostico(
          pronostico: pronostico,
          alturaM: altura.valorM,
          umbrales: umbrales,
          // Si el río todavía no está en alerta pero CARU espera que la pase.
          accion: !esGrave && umbrales?.alertaM != null && pronostico.alturaEsperadaM! >= umbrales!.alertaM!
              ? botonQueHacer
              : null,
        ),
        const SizedBox(height: 16),
      ],

      if (hayNivel && !avisosActivos && alPedirAvisos != null) ...[
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Icon(Icons.notifications_active, color: Colores.primario, size: 28),
            title: Text('¿Querés que el teléfono te avise? Tocá acá', style: tema.titleMedium),
            trailing: Icon(Icons.chevron_right, color: Colores.primario),
            onTap: alPedirAvisos,
          ),
        ),
        const SizedBox(height: 16),
      ],

      // ----- Más detalles: dato de respaldo y enlace al original -----
      Semantics(header: true, child: Text('Más detalles', style: tema.titleSmall?.copyWith(color: Colores.primario))),
      const SizedBox(height: 4),
      if (esEstacion && prefectura != null)
        Text(
          'Prefectura midió ${formatoAltura(prefectura.valorM)} m (${formatoFecha(prefectura.fecha, ahora)}). '
          '${textoTendencia(prefectura, pasado: true)}.',
          style: secundario,
        ),
      if (altura.url != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => abrirEnlace(context, altura.url!),
            icon: const Icon(Icons.open_in_new, size: 22),
            label: const Text('Ver en la página de CARU'),
          ),
        ),
      const SizedBox(height: 16),

      if (hayNivel && umbrales != null && !umbrales.validado)
        const Recuadro(
          icono: Icons.rule,
          tipo: TipoRecuadro.informacion,
          texto: 'Los niveles de alerta y evacuación que usa la app son de referencia: el Cecoed todavía '
              'los está revisando. Tu casa puede mojarse antes o después de esos niveles.',
        ),
      const AvisoOficial(),
    ];
  }
}

class _FilaDato extends StatelessWidget {
  final IconData icono;
  final Widget child;

  const _FilaDato({required this.icono, required this.child});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icono, size: 20, color: Colores.tintaSecundaria),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      );
}

/// El bloque principal de Inicio: zona de color con el nivel, zona blanca con
/// la altura y la tendencia, y pie con fecha y fuente. Es el único lugar de la
/// pantalla con color fuerte.
class _TarjetaEstado extends StatelessWidget {
  final EstiloNivel estilo;
  final String descripcion;
  final Widget? accion;
  final Widget? aviso;
  final List<Widget> lectura;
  final List<Widget> pie;

  const _TarjetaEstado({
    required this.estilo,
    required this.descripcion,
    this.accion,
    this.aviso,
    this.lectura = const [],
    this.pie = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(16),
        // Borde en el tono oscuro del nivel: el amarillo y el naranja solos no
        // se despegan lo suficiente del fondo claro.
        border: Border.all(color: estilo.oscuro, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: estilo.fondo,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  label: 'Nivel: ${estilo.nombre}. $descripcion',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(estilo.icono, color: estilo.texto, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            // Con letra muy grande se achica en vez de cortar la palabra.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                estilo.nombre.toUpperCase(),
                                style: tema.headlineMedium?.copyWith(color: estilo.texto, letterSpacing: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        descripcion,
                        style: tema.bodyLarge?.copyWith(color: estilo.texto, fontWeight: FontWeight.w500, height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (accion != null) ...[const SizedBox(height: 12), accion!],
              ],
            ),
          ),
          ?aviso,
          if (lectura.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(children: lectura),
            ),
          if (pie.isNotEmpty) ...[
            const Divider(),
            Container(
              color: Colores.fondo,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: pie),
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaPronostico extends StatelessWidget {
  final Pronostico pronostico;
  final double alturaM;
  final Umbrales? umbrales;
  final Widget? accion;

  const _TarjetaPronostico({required this.pronostico, required this.alturaM, required this.umbrales, this.accion});

  /// Compara lo que espera CARU con la altura de ahora y con el nivel de
  /// evacuación. Son restas entre valores publicados, no estimaciones propias.
  String _comparacion(double esperada) {
    final partes = <String>[];
    final diferencia = esperada - alturaM;
    if ((diferencia * 100).round() > 0) partes.add('Son ${formatoDiferencia(diferencia)} más que ahora.');
    final evacuacion = umbrales?.evacuacionM;
    if (evacuacion != null) {
      partes.add(esperada >= evacuacion
          ? 'Pasa el nivel de evacuación (${formatoAltura(evacuacion)} m).'
          : 'Queda por debajo del nivel de evacuación (${formatoAltura(evacuacion)} m).');
    }
    return partes.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final p = pronostico;
    final comparacion = _comparacion(p.alturaEsperadaM!);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colores.primarioSuave,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.calendar_month, size: 20, color: Colores.primario),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Lo que espera CARU para los próximos días',
                      style: tema.titleSmall?.copyWith(color: Colores.primario),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CARU estima hasta ${formatoAltura(p.alturaEsperadaM!)} m', style: tema.headlineSmall),
                // La fecha del informe va pegada a la cifra: es su fecha y su fuente.
                if (p.informeFecha != null)
                  Text(
                    'Informe de CARU del ${formatoDia(p.informeFecha!)}',
                    style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria),
                  ),
                if (comparacion.isNotEmpty) ...[const SizedBox(height: 8), Text(comparacion, style: tema.bodyLarge)],
                if (p.texto != null) ...[const SizedBox(height: 8), Text(p.texto!, style: tema.bodyLarge)],
                if (p.caudalM3s != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'La represa de Salto Grande prevé largar hasta ${formatoMiles(p.caudalM3s!)} metros cúbicos de agua por segundo.',
                    style: tema.bodyLarge,
                  ),
                ],
                if (p.urlInforme != null) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  TextButton.icon(
                    onPressed: () => abrirEnlace(context, p.urlInforme!),
                    icon: const Icon(Icons.picture_as_pdf, size: 22),
                    label: const Text('Ver informe (PDF)'),
                  ),
                ],
                if (accion != null) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: accion!), const SizedBox(height: 8)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

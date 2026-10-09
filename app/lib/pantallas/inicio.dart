import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../textos.dart';
import 'comunes.dart';

class PantallaInicio extends StatelessWidget {
  final Datos? datos;
  final Config config;
  final Future<void> Function() alActualizar;

  /// Si los avisos están apagados se invita a prenderlos.
  final bool avisosActivos;
  final VoidCallback? alPedirAvisos;

  /// Solo para pruebas: permite fijar la hora actual.
  final DateTime? ahora;

  const PantallaInicio({
    super.key,
    required this.datos,
    required this.config,
    required this.alActualizar,
    this.avisosActivos = true,
    this.alPedirAvisos,
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
    final actual = datos.actual;
    final altura = actual?.altura;
    final nivel = actual?.nivelVigente(ahora, config.horasSinDato) ?? Nivel.sinDato;
    final estilo = estiloNivel(nivel);

    final sinConexion = datos.sinConexion
        ? Recuadro(
            icono: Icons.wifi_off,
            texto: altura == null
                ? 'No hay conexión a internet.'
                : 'No hay conexión a internet. Se muestra el último dato guardado en este teléfono.',
          )
        : null;

    if (actual == null || altura == null) {
      return [
        ?sinConexion,
        _TarjetaNivel(estilo: estilo, descripcion: descripcionNivel(Nivel.sinDato, null)),
        const SizedBox(height: 16),
        Text(
          datos.sinConexion
              ? 'Conectate a internet y tocá "Reintentar".'
              : 'Probá de nuevo en unos minutos. Si hay personas en peligro, llamá al 911.',
          style: tema.bodyLarge,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: alActualizar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        const SizedBox(height: 20),
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

    return [
      ?sinConexion,
      _TarjetaNivel(estilo: estilo, descripcion: descripcionNivel(nivel, umbrales, altura.valorM)),
      const SizedBox(height: 12),

      // Si el dato es viejo se dice antes del número, para que no se lea como actual.
      if (viejo)
        Recuadro(
          icono: Icons.schedule,
          texto: 'Este dato es de $cuando. Después no llegó información nueva: '
              '${horas > config.horasSinDato ? 'no se puede saber el nivel actual del río.' : 'el río puede estar distinto ahora.'} '
              'Guiate por los avisos del Cecoed.',
        ),

      // Altura: el número grande.
      Semantics(
        label: 'Altura del río: ${formatoAltura(altura.valorM)} metros',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${formatoAltura(altura.valorM)} m',
            style: const TextStyle(fontSize: 84, fontWeight: FontWeight.bold, height: 1.1, color: Colors.black),
          ),
        ),
      ),
      Text(
        'Altura medida en el puerto de Paysandú. No es la altura del agua en tu calle.',
        style: tema.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),

      // Tendencia: flecha y texto.
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconoTendencia(altura), size: 32, color: Colors.black),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              textoTendencia(altura, pasado: viejo),
              style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // Fecha, hora y fuente: toda altura mostrada las lleva.
      Text('Medido: $cuando', style: tema.titleMedium, textAlign: TextAlign.center),
      Text('Fuente: ${altura.fuente ?? 'CARU'}', style: tema.bodyLarge, textAlign: TextAlign.center),
      if (altura.url != null)
        Center(
          child: TextButton.icon(
            onPressed: () => abrirEnlace(context, altura.url!),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ver en la página de CARU'),
          ),
        ),
      const SizedBox(height: 8),

      for (final aviso in actual.avisos)
        // Con el recuadro de dato viejo ya a la vista, no se repite lo mismo.
        if (textoAviso(aviso) != null && !(viejo && aviso == 'dato_desactualizado'))
          Recuadro(icono: Icons.warning_amber, texto: textoAviso(aviso)!),

      if (esEstacion && prefectura != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Prefectura midió ${formatoAltura(prefectura.valorM)} m (${formatoFecha(prefectura.fecha, ahora)}). '
            '${textoTendencia(prefectura, pasado: true)}.',
            style: tema.bodyLarge,
          ),
        ),

      if (pronostico != null && pronostico.vigente && pronostico.alturaEsperadaM != null)
        _TarjetaPronostico(pronostico: pronostico, alturaM: altura.valorM, umbrales: umbrales, ahora: ahora),

      if (!avisosActivos && alPedirAvisos != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: alPedirAvisos,
            icon: const Icon(Icons.notifications_active),
            label: const Text('¿Querés que el teléfono te avise? Tocá acá'),
          ),
        ),

      if (umbrales != null && !umbrales.validado)
        const Recuadro(
          icono: Icons.rule,
          fondo: Color(0xFFEEEEEE),
          texto: 'Los niveles de alerta y evacuación que usa la app son de referencia: el Cecoed todavía '
              'los está revisando. Tu casa puede mojarse antes o después de esos niveles.',
        ),
      const AvisoOficial(),
    ];
  }
}

class _TarjetaNivel extends StatelessWidget {
  final EstiloNivel estilo;
  final String descripcion;

  const _TarjetaNivel({required this.estilo, required this.descripcion});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Nivel: ${estilo.nombre}. $descripcion',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: estilo.fondo,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black54),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(estilo.icono, color: estilo.texto, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  // Con letra muy grande se achica en vez de cortar la palabra.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      estilo.nombre.toUpperCase(),
                      style: tema.headlineMedium?.copyWith(color: estilo.texto, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(descripcion, style: tema.titleMedium?.copyWith(color: estilo.texto)),
          ],
        ),
      ),
    );
  }
}

class _TarjetaPronostico extends StatelessWidget {
  final Pronostico pronostico;
  final double alturaM;
  final Umbrales? umbrales;
  final DateTime ahora;

  const _TarjetaPronostico({required this.pronostico, required this.alturaM, required this.umbrales, required this.ahora});

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
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black54),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Lo que espera CARU para los próximos días',
                style: tema.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'CARU estima hasta ${formatoAltura(p.alturaEsperadaM!)} m',
              style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (comparacion.isNotEmpty) Text(comparacion, style: tema.bodyLarge),
            if (p.informeFecha != null) ...[
              const SizedBox(height: 8),
              Text('Informe de CARU del ${formatoDia(p.informeFecha!)}', style: tema.bodyLarge),
            ],
            if (p.texto != null) ...[const SizedBox(height: 8), Text(p.texto!, style: tema.bodyLarge)],
            if (p.caudalM3s != null) ...[
              const SizedBox(height: 8),
              Text(
                'La represa de Salto Grande prevé largar hasta ${formatoMiles(p.caudalM3s!)} metros cúbicos de agua por segundo.',
                style: tema.bodyLarge,
              ),
            ],
            if (p.urlInforme != null)
              TextButton.icon(
                onPressed: () => abrirEnlace(context, p.urlInforme!),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Ver informe (PDF)'),
              ),
          ],
        ),
      ),
    );
  }
}

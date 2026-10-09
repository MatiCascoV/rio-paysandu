import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../textos.dart';
import 'comunes.dart';

class PantallaInicio extends StatelessWidget {
  final Datos? datos;
  final Config config;
  final Future<void> Function() alActualizar;

  /// Solo para pruebas: permite fijar la hora actual.
  final DateTime? ahora;

  const PantallaInicio({super.key, required this.datos, required this.config, required this.alActualizar, this.ahora});

  @override
  Widget build(BuildContext context) {
    final datos = this.datos;
    if (datos == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Cargando el nivel del río…')],
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
              : 'En este momento no hay un dato del nivel del río. Probá de nuevo en unos minutos.',
          style: tema.bodyLarge,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: alActualizar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        const SizedBox(height: 20),
        const AvisoOficial(),
      ];
    }

    final horas = ahora.difference(altura.fecha).inMinutes / 60;
    final pronostico = actual.pronostico;
    final esEstacion = (altura.fuente ?? '').contains('estación');
    final prefectura = actual.prefectura;

    return [
      ?sinConexion,
      _TarjetaNivel(estilo: estilo, descripcion: descripcionNivel(nivel, datos.umbrales)),
      const SizedBox(height: 16),

      // Altura actual: el número grande.
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
      const SizedBox(height: 8),

      // Tendencia: flecha y texto.
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconoTendencia(altura), size: 32, color: Colors.black),
          const SizedBox(width: 8),
          Flexible(
            child: Text(textoTendencia(altura), style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      const SizedBox(height: 16),

      // Fecha, hora y fuente: toda altura mostrada las lleva.
      Text('Actualizado: ${formatoFecha(altura.fecha, ahora)}', style: tema.titleMedium, textAlign: TextAlign.center),
      Text('Fuente: ${altura.fuente ?? 'CARU'}', style: tema.bodyLarge, textAlign: TextAlign.center),
      if (altura.url != null)
        Center(
          child: TextButton.icon(
            onPressed: () => abrirEnlace(context, altura.url!),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ver fuente'),
          ),
        ),
      const SizedBox(height: 8),

      if (horas > config.horasAvisoDatoViejo)
        Recuadro(
          icono: Icons.schedule,
          texto: horas > config.horasSinDato
              ? 'El último dato tiene más de ${config.horasSinDato} horas. No se puede saber el nivel actual del río.'
              : 'Este dato tiene más de ${config.horasAvisoDatoViejo} horas. El río puede haber cambiado.',
        ),
      for (final aviso in actual.avisos)
        if (textoAviso(aviso) != null) Recuadro(icono: Icons.warning_amber, texto: textoAviso(aviso)!),

      if (esEstacion && prefectura != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Lectura de Prefectura (${formatoFecha(prefectura.fecha, ahora)}): '
            '${formatoAltura(prefectura.valorM)} m. ${textoTendencia(prefectura)}.',
            style: tema.bodyLarge,
          ),
        ),

      if (pronostico != null && pronostico.vigente && pronostico.alturaEsperadaM != null)
        _TarjetaPronostico(pronostico: pronostico),

      if (datos.umbrales != null && !datos.umbrales!.validado)
        const Recuadro(
          icono: Icons.rule,
          fondo: Color(0xFFEEEEEE),
          texto: 'Los niveles de alerta y evacuación que usa la app son provisorios: '
              'todavía no fueron confirmados por el Cecoed.',
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
        decoration: BoxDecoration(color: estilo.fondo, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(estilo.icono, color: estilo.texto, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    estilo.nombre.toUpperCase(),
                    style: tema.headlineMedium?.copyWith(color: estilo.texto, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(descripcion, style: tema.bodyLarge?.copyWith(color: estilo.texto)),
          ],
        ),
      ),
    );
  }
}

class _TarjetaPronostico extends StatelessWidget {
  final Pronostico pronostico;

  const _TarjetaPronostico({required this.pronostico});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final p = pronostico;
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
            Text('Pronóstico de CARU', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'CARU estima hasta ${formatoAltura(p.alturaEsperadaM!)} m',
              style: tema.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (p.informeFecha != null) Text('Informe del ${formatoDia(p.informeFecha!)}', style: tema.bodyLarge),
            if (p.texto != null) ...[const SizedBox(height: 8), Text(p.texto!, style: tema.bodyLarge)],
            if (p.caudalM3s != null) ...[
              const SizedBox(height: 8),
              Text(
                'Salto Grande prevé largar hasta ${formatoMiles(p.caudalM3s!)} metros cúbicos por segundo.',
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

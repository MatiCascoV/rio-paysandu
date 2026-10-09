import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

/// Pantalla principal. Solo dos superficies: la franja de color con el nivel y
/// la escalera de niveles. Todo lo demás va suelto sobre el fondo, separado con
/// aire o una línea fina. Los bloques van siempre en el mismo orden; según el
/// estado algunos aparecen y otros no.
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: _contenido(context, datos, ahora ?? DateTime.now()),
      ),
    );
  }

  List<Widget> _contenido(BuildContext context, Datos datos, DateTime ahora) {
    final tema = Theme.of(context).textTheme;
    final apoyo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    final actual = datos.actual;
    final altura = actual?.altura;
    final nivel = actual?.nivelVigente(ahora, config.horasSinDato) ?? Nivel.sinDato;
    final estilo = estiloNivel(nivel);

    final sinConexion = datos.sinConexion
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.wifi_off, size: 24, color: Colores.tinta),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    altura == null ? 'Sin conexión a internet.' : 'Sin conexión. Dato guardado en este teléfono.',
                    style: tema.titleMedium,
                  ),
                ),
              ],
            ),
          )
        : null;
    final deslinde = _Deslinde(alTocar: alVerQueHacer);

    // ----- Sin ninguna altura para mostrar -----
    if (actual == null || altura == null) {
      return [
        ?sinConexion,
        _FranjaNivel(estilo: estilo, frase: descripcionNivel(Nivel.sinDato, null)),
        const SizedBox(height: 24),
        Text(
          datos.sinConexion
              ? 'Conectate a internet y tocá Reintentar.'
              : 'Probá de nuevo en unos minutos. Si hay personas en peligro, llamá al 911.',
          style: tema.bodyLarge,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: alActualizar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        if (alVerQueHacer != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: alVerQueHacer, child: const Text('Ver qué hacer')),
        ],
        const Separador(arriba: 24, abajo: 0),
        deslinde,
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
    final conEscalera = hayNivel && umbrales != null && umbralesOrdenados(umbrales).isNotEmpty;
    final esGrave = nivel == Nivel.alerta || nivel == Nivel.evacuacion;
    // El dato pierde protagonismo cuando ya no se puede tomar como actual.
    final colorDato = viejo ? Colores.tintaSecundaria : Colores.tinta;
    final avisos = [
      for (final aviso in actual.avisos)
        // Con el aviso de dato viejo ya a la vista, no se repite lo mismo.
        if (textoAviso(aviso) != null &&
            !(viejo && (aviso == 'dato_desactualizado' || aviso == 'fuente_no_disponible')))
          textoAviso(aviso)!,
    ];
    final hayPronostico = pronostico != null && pronostico.vigente && pronostico.alturaEsperadaM != null;
    final invitarAvisos = hayNivel && !avisosActivos && alPedirAvisos != null;

    return [
      ?sinConexion,

      // ----- Nivel: el único color fuerte de la pantalla -----
      _FranjaNivel(
        estilo: estilo,
        frase: descripcionNivel(nivel, umbrales, viejo: viejo),
        alVerQueHacer: esGrave ? alVerQueHacer : null,
      ),

      // Si el dato es viejo se dice antes del número, para que no se lea como actual.
      if (viejo) ...[
        const SizedBox(height: 12),
        Recuadro(
          icono: Icons.schedule,
          texto: 'Dato de $cuando. Después no llegó información nueva'
              '${horas > config.horasSinDato ? '.' : ': el río puede estar distinto.'}',
        ),
      ],
      SizedBox(height: viejo ? 16 : 24),

      // ----- Altura, con su fecha, hora y fuente pegadas -----
      if (viejo || datos.sinConexion)
        Text('Último dato', style: tema.titleMedium?.copyWith(color: Colores.tintaSecundaria), textAlign: TextAlign.center),
      Semantics(
        container: true,
        excludeSemantics: true,
        label: 'Altura del río: ${formatoAltura(altura.valorM)} metros. Medido $cuando. '
            'Fuente: ${fuenteCorta(altura.fuente)}.',
        child: Column(
          children: [
            // El número no crece con la letra del sistema (ya es enorme).
            MediaQuery.withClampedTextScaling(
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
            const SizedBox(height: 8),
            // Toda altura mostrada lleva fecha, hora y fuente, siempre a la vista.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              children: [
                Text(conMayuscula(cuando), style: tema.titleMedium),
                Text('· ${fuenteCorta(altura.fuente)}', style: tema.bodyLarge),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // Tendencia: flecha y texto.
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconoTendencia(altura), size: 28, color: viejo ? Colores.tintaSecundaria : Colores.primario),
          const SizedBox(width: 8),
          Flexible(
            child: Text(textoTendencia(altura, pasado: viejo), style: tema.titleLarge?.copyWith(color: colorDato)),
          ),
        ],
      ),

      for (final texto in avisos) ...[const SizedBox(height: 16), Recuadro(icono: Icons.warning_amber, texto: texto)],
      const SizedBox(height: 24),

      // ----- Dónde está el río respecto de los niveles -----
      if (conEscalera)
        EscaleraNiveles(
          alturaM: altura.valorM,
          umbrales: umbrales,
          viejo: viejo,
          descripcion: descripcionEscala(altura.valorM, cuando, viejo, umbrales),
        )
      else
        Text(
          'Medido en el puerto de Paysandú: no es la altura del agua en tu calle.',
          style: apoyo,
          textAlign: TextAlign.center,
        ),
      const Separador(arriba: 24, abajo: 0),

      if (hayPronostico) ...[
        const SizedBox(height: 16),
        _Pronostico(
          pronostico: pronostico,
          umbrales: umbrales,
          // Si el río todavía no está en alerta pero CARU espera que la pase.
          alVerQueHacer: !esGrave && umbrales?.alertaM != null && pronostico.alturaEsperadaM! >= umbrales!.alertaM!
              ? alVerQueHacer
              : null,
        ),
        const Separador(arriba: 8, abajo: 0),
      ],

      if (invitarAvisos) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 56,
          leading: Icon(Icons.notifications_active, color: Colores.primario),
          title: Text('Recibir avisos en este teléfono', style: tema.titleMedium),
          trailing: Icon(Icons.chevron_right, color: Colores.primario),
          onTap: alPedirAvisos,
        ),
        const Divider(),
      ],

      // ----- Detalles: dato de respaldo y enlace al original -----
      const SizedBox(height: 16),
      if (esEstacion && prefectura != null)
        Text(
          'Prefectura midió ${formatoAltura(prefectura.valorM)} m ${formatoFecha(prefectura.fecha, ahora)}.',
          style: apoyo,
        ),
      if (altura.url != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => abrirEnlace(context, altura.url!),
            child: const Text('Ver en la página de CARU'),
          ),
        ),
      const Separador(arriba: 8, abajo: 0),
      deslinde,
    ];
  }
}

/// Franja de color con el nivel: ícono, palabra, una frase y, en alerta o
/// evacuación, el botón para ir a "Qué hacer".
class _FranjaNivel extends StatelessWidget {
  final EstiloNivel estilo;
  final String frase;
  final VoidCallback? alVerQueHacer;

  const _FranjaNivel({required this.estilo, required this.frase, this.alVerQueHacer});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    // El amarillo casi no se despega de un fondo blanco: es la única franja con contorno.
    final contorno = estilo.fondo == const Color(0xFFFFD600) && !Colores.oscuro;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: estilo.fondo,
        borderRadius: radioSuperficie,
        border: contorno ? Border.all(color: estilo.oscuro, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: 'Nivel: ${estilo.nombre}. $frase',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(estilo.icono, color: estilo.texto, size: 32),
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
                const SizedBox(height: 6),
                Text(frase, style: tema.bodyLarge?.copyWith(color: estilo.texto)),
              ],
            ),
          ),
          if (alVerQueHacer != null) ...[
            const SizedBox(height: 14),
            // El botón toma el color del texto de la franja: contrasta en todos los niveles.
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: estilo.texto,
                foregroundColor: estilo.texto == Colors.white ? const Color(0xFF111B24) : Colors.white,
              ),
              onPressed: alVerQueHacer,
              child: const Text('Ver qué hacer'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pronóstico de CARU como un dato: el máximo esperado. El texto del informe
/// queda plegado. Solo existe durante crecidas, cuando CARU publica informes.
class _Pronostico extends StatelessWidget {
  final Pronostico pronostico;
  final Umbrales? umbrales;
  final VoidCallback? alVerQueHacer;

  const _Pronostico({required this.pronostico, required this.umbrales, this.alVerQueHacer});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final p = pronostico;
    final esperada = p.alturaEsperadaM!;
    final evacuacion = umbrales?.evacuacionM;
    // Comparación entre dos valores publicados, no una estimación propia.
    final comparacion = evacuacion == null
        ? null
        : (esperada * 100).round() >= (evacuacion * 100).round()
            ? 'Pasa el nivel de evacuación.'
            : 'Queda ${formatoDiferencia(evacuacion - esperada)} por debajo de evacuación.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(header: true, child: Text('Máximo esperado por CARU', style: tema.titleMedium)),
                if (p.informeFecha != null)
                  Text('Informe del ${formatoDia(p.informeFecha!)}',
                      style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
              ],
            ),
            Text('${formatoAltura(esperada)} m', style: tema.headlineMedium),
          ],
        ),
        if (comparacion != null) ...[const SizedBox(height: 8), Text(comparacion, style: tema.bodyLarge)],
        if (alVerQueHacer != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: alVerQueHacer, child: const Text('Ver qué hacer')),
        ],
        if (p.texto != null || p.caudalM3s != null || p.urlInforme != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: Colores.primario,
            collapsedIconColor: Colores.primario,
            title: Text('Leer el informe', style: tema.titleMedium?.copyWith(color: Colores.primario)),
            children: [
              if (p.texto != null) Text(p.texto!, style: tema.bodyLarge),
              if (p.caudalM3s != null) ...[
                const SizedBox(height: 8),
                Text('Salto Grande prevé largar hasta ${formatoMiles(p.caudalM3s!)} m³ por segundo.',
                    style: tema.bodyLarge),
              ],
              if (p.urlInforme != null)
                TextButton(
                  onPressed: () => abrirEnlace(context, p.urlInforme!),
                  child: const Text('Abrir el informe de CARU (PDF)'),
                ),
            ],
          ),
      ],
    );
  }
}

/// Deslinde corto al pie de Inicio; el texto completo está en "Qué hacer".
class _Deslinde extends StatelessWidget {
  final VoidCallback? alTocar;

  const _Deslinde({required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Semantics(
      button: alTocar != null,
      child: InkWell(
        onTap: alTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textoDeslindeCorto, style: tema.bodyMedium),
                if (alTocar != null)
                  Text(
                    'Leer más en Qué hacer',
                    style: tema.bodyMedium?.copyWith(
                      color: Colores.primario,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
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

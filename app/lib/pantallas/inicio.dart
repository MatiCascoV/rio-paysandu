import 'package:flutter/material.dart';

import '../datos.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';
import 'grafico.dart';
import 'olas.dart';

/// Lo que define cómo se tiñe Inicio: el nivel vigente y si el dato ya es viejo.
({Nivel nivel, bool viejo}) estadoInicio(Datos? datos, Config config, DateTime ahora) {
  final actual = datos?.actual;
  final altura = actual?.altura;
  final nivel = actual?.nivelVigente(ahora, config.horasSinDato) ?? Nivel.sinDato;
  final viejo = altura != null && ahora.difference(altura.fecha).inMinutes / 60 > config.horasAvisoDatoViejo;
  return (nivel: nivel, viejo: viejo);
}

/// Color del tinte de Inicio (arriba de la pantalla y la barra superior).
/// Sin dato o con un dato viejo, gris: el color no puede decir más que el dato.
Color tinteInicio(Datos? datos, Config config, DateTime ahora) {
  final e = estadoInicio(datos, config, ahora);
  return ColoresNivel.tinte(e.viejo ? Nivel.sinDato : e.nivel);
}

/// Fondo de Inicio: el tinte del nivel arriba, que se funde con el fondo de
/// la app hacia el 62 % de la altura visible.
Gradient degradeInicio(Color tinte) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [tinte, tinte, Colores.fondo],
      stops: const [0, 0.18, 0.62],
    );

/// Qué parte del bloque de la altura cubre el agua: la altura sobre la de
/// evacuación (con un mínimo, para que siempre se vea algo de agua).
double fraccionAgua({required double? alturaM, required Umbrales? umbrales, required bool sinNivel}) {
  const minimo = 0.15;
  if (sinNivel || alturaM == null) return minimo;
  final evacuacion = umbrales?.evacuacionM;
  if (evacuacion == null || evacuacion <= 0) return 0.3;
  return (alturaM / evacuacion).clamp(minimo, 1.0);
}

/// Avisos del lector que siguen a la vista; los demás van en "Más datos".
const _avisosGraves = {
  'dato_desactualizado',
  'fuente_no_disponible',
  'dato_a_verificar',
  'dato_fuera_de_rango',
  'umbrales_invalidos',
};

/// Pantalla principal. La pantalla se tiñe con el color del nivel; arriba va
/// el nombre del nivel en grande, después la altura apoyada sobre el agua, el
/// gráfico de la semana y, plegado, todo lo demás. Los bloques van siempre en
/// el mismo orden; según el estado algunos aparecen y otros no.
class PantallaInicio extends StatelessWidget {
  final Datos? datos;
  final Config config;
  final Future<void> Function() alActualizar;

  /// Si los avisos están apagados se invita a prenderlos.
  final bool avisosActivos;
  final VoidCallback? alPedirAvisos;
  final VoidCallback? alVerQueHacer;
  final VoidCallback? alVerGrafico;

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
    this.alVerGrafico,
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: _contenido(context, datos, ahora ?? DateTime.now()),
      ),
    );
  }

  List<Widget> _contenido(BuildContext context, Datos datos, DateTime ahora) {
    final tema = Theme.of(context).textTheme;
    final apoyo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    final actual = datos.actual;
    final altura = actual?.altura;
    final (:nivel, :viejo) = estadoInicio(datos, config, ahora);

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
    final pie = _Pie(alTocar: alVerQueHacer);

    // ----- Sin ninguna altura para mostrar -----
    if (actual == null || altura == null) {
      return [
        ?sinConexion,
        _CabeceraNivel(nivel: Nivel.sinDato, frase: descripcionNivel(Nivel.sinDato, null)),
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
        const SizedBox(height: 24),
        pie,
      ];
    }

    final horas = ahora.difference(altura.fecha).inMinutes / 60;
    final cuando = formatoFecha(altura.fecha, ahora);
    final pronostico = actual.pronostico;
    final esEstacion = (altura.fuente ?? '').contains('estación');
    final prefectura = actual.prefectura;
    final umbrales = datos.umbrales;
    final hayNivel = nivel != Nivel.sinDato;
    final esGrave = nivel == Nivel.alerta || nivel == Nivel.evacuacion;
    // El dato pierde protagonismo cuando ya no se puede tomar como actual.
    final colorDato = viejo ? Colores.tintaSecundaria : Colores.tinta;
    final avisos = [
      for (final aviso in actual.avisos)
        // Con el aviso de dato viejo ya a la vista, no se repite lo mismo.
        if (textoAviso(aviso) != null &&
            !(viejo && (aviso == 'dato_desactualizado' || aviso == 'fuente_no_disponible')))
          (texto: textoAviso(aviso)!, grave: _avisosGraves.contains(aviso)),
    ];
    final hayPronostico = pronostico != null && pronostico.vigente && pronostico.alturaEsperadaM != null;
    final invitarAvisos = hayNivel && !avisosActivos && alPedirAvisos != null;
    final desde = ahora.subtract(const Duration(days: 7));
    final semana = puntosDesde(datos.historial, desde);
    // Gris si no hay nivel o si el dato ya es viejo: el agua tampoco puede decir más que el dato.
    final nivelAgua = viejo ? Nivel.sinDato : nivel;

    final masDatos = <Widget>[
      if (esEstacion && prefectura != null)
        Text('Prefectura midió ${formatoAltura(prefectura.valorM)} m ${formatoFecha(prefectura.fecha, ahora)}.',
            style: apoyo),
      if (!esGrave) Text('Medido en el puerto de Paysandú: no es la altura del agua en tu calle.', style: apoyo),
      if (umbrales != null && !umbrales.validado)
        Text('Los niveles son de referencia; el Cecoed todavía los está revisando.', style: apoyo),
      for (final a in avisos.where((a) => !a.grave)) Recuadro(icono: Icons.info_outline, texto: a.texto),
      if (enlacePermitido(altura.url))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => abrirEnlace(context, altura.url!),
            child: const Text('Ver en la página de CARU'),
          ),
        ),
      if (invitarAvisos)
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 56,
          leading: Icon(Icons.notifications_active, color: Colores.primario),
          title: Text('Recibir avisos en este teléfono', style: tema.titleMedium),
          trailing: Icon(Icons.chevron_right, color: Colores.primario),
          onTap: alPedirAvisos,
        ),
    ];

    return [
      ?sinConexion,

      // ----- Nivel: nombre grande y la frase -----
      _CabeceraNivel(
        nivel: nivel,
        frase: descripcionNivel(nivel, umbrales,
            alturaM: altura.valorM,
            viejo: viejo,
            umbralesInvalidos: actual.avisos.contains('umbrales_invalidos')),
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
      const SizedBox(height: 16),

      // El rótulo va fuera del bloque: en tinta secundaria, no puede quedar sobre el agua.
      if (viejo || datos.sinConexion)
        Text('Último dato',
            style: tema.titleMedium?.copyWith(color: Colores.tintaSecundaria), textAlign: TextAlign.center),

      // ----- Altura, con su fecha, hora y fuente pegadas, apoyada sobre el agua -----
      _BloqueAltura(
        nivelAgua: nivelAgua,
        fraccion: fraccionAgua(alturaM: altura.valorM, umbrales: umbrales, sinNivel: !hayNivel || viejo),
        child: Column(
          children: [
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
                            TextSpan(
                                text: ' m', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w600, letterSpacing: 0)),
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
            const SizedBox(height: 10),
            // Tendencia: flecha y texto.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconoTendencia(altura), size: 28, color: viejo ? Colores.tintaSecundaria : Colores.tinta),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(textoTendencia(altura, pasado: viejo), style: tema.titleLarge?.copyWith(color: colorDato)),
                ),
              ],
            ),
          ],
        ),
      ),

      // ----- En alerta o evacuación: qué hacer, a mano -----
      if (esGrave) ...[
        const SizedBox(height: 16),
        _BotonQueHacer(nivel: nivel, alTocar: alVerQueHacer),
        const SizedBox(height: 10),
        Text('Medido en el puerto: no es la altura del agua en tu calle.', style: apoyo, textAlign: TextAlign.center),
      ],

      for (final a in avisos.where((a) => a.grave)) ...[
        const SizedBox(height: 16),
        Recuadro(icono: Icons.warning_amber, texto: a.texto),
      ],

      // ----- La semana, de un vistazo -----
      if (semana.isNotEmpty) ...[
        const SizedBox(height: 20),
        _GraficoSemana(puntos: semana, umbrales: umbrales, desde: desde, hasta: ahora, alVerMas: alVerGrafico),
      ],
      const SizedBox(height: 12),

      if (hayPronostico) ...[
        const Divider(),
        _Pronostico(
          pronostico: pronostico,
          umbrales: umbrales,
          // Si el río todavía no está en alerta pero CARU espera que la pase.
          alVerQueHacer: !esGrave && umbrales?.alertaM != null && pronostico.alturaEsperadaM! >= umbrales!.alertaM!
              ? alVerQueHacer
              : null,
        ),
      ],

      if (masDatos.isNotEmpty) ...[
        const Divider(),
        _Plegable(
          titulo: Text('Más datos', style: tema.titleMedium),
          children: [
            for (final (i, w) in masDatos.indexed) ...[if (i > 0) const SizedBox(height: 8), w],
          ],
        ),
      ],
      const Divider(),
      pie,
    ];
  }
}

/// Ícono y nombre del nivel en grande, en el tono de su familia, con la frase
/// debajo. Para el lector de pantalla es un solo nodo: "Nivel: Alerta. …".
class _CabeceraNivel extends StatelessWidget {
  final Nivel nivel;
  final String frase;

  const _CabeceraNivel({required this.nivel, required this.frase});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final estilo = estiloNivel(nivel);
    final color = ColoresNivel.familia(nivel);
    return Semantics(
      container: true,
      label: 'Nivel: ${estilo.nombre}. ${unidadesEnPalabras(frase)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(estilo.icono, color: color, size: 32),
              const SizedBox(width: 10),
              Expanded(
                // Con letra muy grande se achica en vez de cortar la palabra.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    estilo.nombre.toUpperCase(),
                    style: TextStyle(fontSize: 34, height: 1.05, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(frase, style: tema.bodyLarge),
        ],
      ),
    );
  }
}

/// El número y lo que lo acompaña, con aire abajo y el agua del nivel de
/// borde a borde de la pantalla. El agua sube con el río: cubre [fraccion] del
/// bloque, desde abajo, y cambia de altura con una transición suave.
class _BloqueAltura extends StatelessWidget {
  final Nivel nivelAgua;
  final double fraccion;
  final Widget child;

  /// Aire debajo de la tendencia, donde el agua se ve siempre.
  static const aire = 54.0;

  /// Lo que el agua sale del margen de la lista, hasta el borde de la pantalla.
  static const margen = 16.0;

  const _BloqueAltura({required this.nivelAgua, required this.fraccion, required this.child});

  @override
  Widget build(BuildContext context) {
    final quieto = MediaQuery.disableAnimationsOf(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -margen,
          right: -margen,
          top: 0,
          bottom: 0,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: quieto ? fraccion : 0.15, end: fraccion),
            duration: quieto ? Duration.zero : const Duration(milliseconds: 1200),
            curve: Curves.easeOut,
            builder: (context, f, agua) => Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(widthFactor: 1, heightFactor: f, child: agua),
            ),
            child: OlasNivel(
              color: ColoresNivel.ola(nivelAgua),
              opacidades: ColoresNivel.opacidadesOlas(nivelAgua),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.only(top: 4, bottom: aire), child: child),
      ],
    );
  }
}

/// "Ver qué hacer" de ancho completo, en el color del nivel.
class _BotonQueHacer extends StatelessWidget {
  final Nivel nivel;
  final VoidCallback? alTocar;

  const _BotonQueHacer({required this.nivel, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final (fondo, texto) = ColoresNivel.boton(nivel);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: fondo,
        foregroundColor: texto,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
      ),
      onPressed: alTocar,
      child: const Text('Ver qué hacer'),
    );
  }
}

/// Los últimos 7 días en chico, sobre una superficie translúcida, con un
/// acceso a la pestaña Gráfico.
class _GraficoSemana extends StatelessWidget {
  final List<PuntoHistorial> puntos;
  final Umbrales? umbrales;
  final DateTime desde;
  final DateTime hasta;
  final VoidCallback? alVerMas;

  const _GraficoSemana({
    required this.puntos,
    required this.umbrales,
    required this.desde,
    required this.hasta,
    required this.alVerMas,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final titulo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
      decoration: BoxDecoration(
        color: Colores.superficie.withValues(alpha: 0.72),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text('Últimos 7 días', style: titulo))),
              if (alVerMas != null)
                Semantics(
                  button: true,
                  label: 'Ver más en la pestaña Gráfico',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: alVerMas,
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Ver más', style: titulo?.copyWith(color: Colores.primario, fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right, size: 20, color: Colores.primario),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Semantics(
            container: true,
            label: 'Gráfico de la altura del río en los últimos 7 días. '
                '${unidadesEnPalabras(resumenHistorial(puntos))}',
            excludeSemantics: true,
            // Dentro del gráfico la letra no crece: los rótulos no se pisan.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: SizedBox(
                height: 155,
                child: GraficoAltura(puntos: puntos, umbrales: umbrales, desde: desde, hasta: hasta, compacto: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila que se despliega, sin bordes propios (los separa una línea fina).
class _Plegable extends StatelessWidget {
  final Widget titulo;
  final List<Widget> children;

  const _Plegable({required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        minTileHeight: 56,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        expandedAlignment: Alignment.centerLeft,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: Colores.primario,
        collapsedIconColor: Colores.primario,
        title: titulo,
        children: children,
      );
}

/// Pronóstico de CARU en una fila: el máximo esperado y la fecha del informe.
/// Al desplegarla, la comparación con evacuación, el texto, el caudal y el
/// PDF. Solo existe durante crecidas, cuando CARU publica informes.
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
    final informe = p.informeFecha;
    // Comparación entre dos valores publicados, no una estimación propia.
    final comparacion = evacuacion == null
        ? null
        : (esperada * 100).round() >= (evacuacion * 100).round()
            ? 'Pasa el nivel de evacuación.'
            : 'Queda ${formatoDiferencia(evacuacion - esperada)} por debajo de evacuación.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Plegable(
          titulo: Text.rich(
            TextSpan(
              text: 'CARU espera hasta ',
              children: [
                TextSpan(text: '${formatoAltura(esperada)} m', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (informe != null) TextSpan(text: ' · informe del ${informe.day}/${informe.month}'),
              ],
            ),
            style: tema.bodyLarge,
          ),
          children: [
            if (comparacion != null) Text(comparacion, style: tema.bodyLarge),
            if (p.texto != null) ...[const SizedBox(height: 8), Text(p.texto!, style: tema.bodyLarge)],
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
        if (alVerQueHacer != null) ...[
          OutlinedButton(onPressed: alVerQueHacer, child: const Text('Ver qué hacer')),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Pie de una línea; el deslinde completo está en "Qué hacer".
class _Pie extends StatelessWidget {
  final VoidCallback? alTocar;

  const _Pie({required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(textoDeslindeCorto, style: estilo),
          if (alTocar != null) ...[
            Text(' · ', style: estilo),
            Semantics(
              button: true,
              label: 'Más info: el aviso completo, en Qué hacer',
              excludeSemantics: true,
              child: InkWell(
                onTap: alTocar,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    widthFactor: 1,
                    child: Text(
                      'Más info',
                      style: estilo?.copyWith(
                        color: Colores.primario,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

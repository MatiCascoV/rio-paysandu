import 'package:flutter/material.dart';

import '../datos.dart';
import '../tema.dart';
import 'comunes.dart';

// Recomendaciones generales ante crecidas. Pendiente: que el Cecoed las revise.
const _recomendaciones = <(String, List<String>)>[
  (
    'Si el río está creciendo',
    [
      'Seguí la información oficial del Cecoed (el centro de emergencias de Paysandú) y del Sinae.',
      'Guardá documentos, medicamentos, agua, linterna y cargador en una bolsa que no se moje.',
      'Subí a un lugar alto lo que no quieras perder.',
      'Acordá con tu familia a dónde irían y pensá a dónde llevar a tus mascotas.',
      'Avisá a vecinos que puedan necesitar ayuda para salir.',
    ],
  ),
  (
    'Si el agua se acerca a tu casa',
    [
      'Si te indican evacuar, hacelo. No esperes a último momento ni a que sea de noche.',
      'Antes de salir, cortá la electricidad y cerrá el gas.',
      'No cruces calles ni zonas inundadas, ni a pie ni en vehículo.',
      'Si hay personas en peligro, llamá al 911.',
    ],
  ),
  (
    'Cuando el agua baja',
    [
      'Volvé a tu casa recién cuando las autoridades lo indiquen.',
      'No conectes la electricidad hasta que la instalación esté seca y revisada.',
      'Limpiá y desinfectá todo lo que tocó el agua.',
      'No consumas alimentos ni agua que hayan estado en contacto con la inundación.',
    ],
  ),
];

class PantallaQueHacer extends StatelessWidget {
  final Config config;
  final ScrollController? controlador;

  const PantallaQueHacer({super.key, required this.config, this.controlador});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    // Los teléfonos se muestran agrupados por momento, en el orden de la configuración.
    final grupos = <String, List<Contacto>>{};
    for (final c in config.contactos) {
      grupos.putIfAbsent(c.grupo.isEmpty ? c.nombre : c.grupo, () => []).add(c);
    }

    return ListView(
      controller: controlador,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Semantics(header: true, child: Text('Teléfonos', style: tema.titleLarge)),
        const SizedBox(height: 12),
        // Una sola tarjeta con todos los teléfonos, separados por líneas finas.
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (g, entrada) in grupos.entries.indexed) ...[
                  if (g > 0) Divider(indent: 16, endIndent: 16, color: Colores.bordeSuave),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(entrada.key, style: tema.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  for (final c in entrada.value) _FilaTelefono(contacto: c, grupo: entrada.key),
                ],
              ],
            ),
          ),
        ),

        // Deslinde de responsabilidad completo.
        const Separador(arriba: 24, abajo: 24),
        Semantics(header: true, child: Text('Sobre esta app', style: tema.titleMedium)),
        const SizedBox(height: 8),
        Text(textoDeslinde, style: tema.bodyLarge),

        for (final (titulo, items) in _recomendaciones) ...[
          const SizedBox(height: 32),
          Semantics(header: true, child: Text(titulo, style: tema.titleLarge)),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 10, left: 2),
                    decoration: BoxDecoration(color: Colores.tintaSecundaria, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item, style: tema.bodyLarge)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Un teléfono: el número grande y un botón que dice "Llamar".
class _FilaTelefono extends StatelessWidget {
  final Contacto contacto;
  final String grupo;

  const _FilaTelefono({required this.contacto, required this.grupo});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = contacto;
    void llamar() => abrirEnlace(context, 'tel:${c.telefono.replaceAll(' ', '')}');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Con letra muy grande el número se achica en vez de cortarse.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        c.telefono,
                        style: tema.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                    if (c.detalle != null)
                      Text(c.detalle!, style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Para el lector de pantalla: a quién llama, con el número dígito por
            // dígito (si no, se lee como un número de millones).
            Semantics(
              button: true,
              excludeSemantics: true,
              label: 'Llamar a ${c.nombre}, ${c.telefono.replaceAll(' ', '').split('').join(' ')}. $grupo',
              onTap: llamar,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(112, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: llamar,
                icon: const Icon(Icons.phone, size: 20),
                label: const Text('Llamar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

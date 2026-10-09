import 'package:flutter/material.dart';

import '../datos.dart';
import '../tema.dart';
import 'comunes.dart';

// Recomendaciones generales ante crecidas. Pendiente: que el Cecoed las revise.
const _recomendaciones = <(String, IconData, List<String>)>[
  (
    'Si el río está creciendo',
    Icons.backpack,
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
    Icons.directions_walk,
    [
      'Si te indican evacuar, hacelo. No esperes a último momento ni a que sea de noche.',
      'Antes de salir, cortá la electricidad y cerrá el gas.',
      'No cruces calles ni zonas inundadas, ni a pie ni en vehículo.',
      'Si hay personas en peligro, llamá al 911.',
    ],
  ),
  (
    'Cuando el agua baja',
    Icons.home,
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
    final secundario = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);
    return ListView(
      controller: controlador,
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(header: true, child: Text('Teléfonos', style: tema.titleLarge)),
        const SizedBox(height: 8),
        for (final c in config.contactos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              // Para el lector de pantalla: un botón que dice a quién llama, con el
              // número dígito por dígito (si no, se lee como un número de millones).
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: 'Llamar a ${c.nombre}, ${c.telefono.replaceAll(' ', '').split('').join(' ')}. ${c.detalle ?? ''}',
                onTap: () => abrirEnlace(context, 'tel:${c.telefono.replaceAll(' ', '')}'),
                child: InkWell(
                  onTap: () => abrirEnlace(context, 'tel:${c.telefono.replaceAll(' ', '')}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(color: Colores.primario, shape: BoxShape.circle),
                          child: const Icon(Icons.phone, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c.nombre}: ${c.telefono}', style: tema.titleMedium),
                              Text('${c.detalle == null ? '' : '${c.detalle}. '}Tocá para llamar.', style: secundario),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        // Deslinde de responsabilidad, junto a los teléfonos de los canales oficiales.
        const AvisoOficial(),
        const SizedBox(height: 12),
        for (final (titulo, icono, items) in _recomendaciones) ...[
          Row(children: [
            Icon(icono, size: 28, color: Colores.primario),
            const SizedBox(width: 8),
            Expanded(child: Semantics(header: true, child: Text(titulo, style: tema.titleLarge))),
          ]),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final (i, item) in items.indexed) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 10),
                          decoration: const BoxDecoration(color: Colores.primario, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(item, style: tema.bodyLarge)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../datos.dart';
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

  const PantallaQueHacer({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(header: true, child: Text('Teléfonos', style: tema.titleLarge)),
        const SizedBox(height: 8),
        for (final c in config.contactos)
          Card(
            // Para el lector de pantalla: un botón que dice a quién llama, con el
            // número dígito por dígito (si no, "150 1353" se lee como un millón y pico).
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: 'Llamar a ${c.nombre}, ${c.telefono.replaceAll(' ', '').split('').join(' ')}. ${c.detalle ?? ''}',
              onTap: () => abrirEnlace(context, 'tel:${c.telefono.replaceAll(' ', '')}'),
              child: ListTile(
                leading: const Icon(Icons.phone, size: 32),
                title: Text('${c.nombre}: ${c.telefono}', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Text('${c.detalle == null ? '' : '${c.detalle}. '}Tocá para llamar.', style: tema.bodyLarge),
                onTap: () => abrirEnlace(context, 'tel:${c.telefono.replaceAll(' ', '')}'),
                trailing: const Icon(Icons.call),
              ),
            ),
          ),
        const SizedBox(height: 16),
        for (final (titulo, icono, items) in _recomendaciones) ...[
          Row(children: [
            Icon(icono, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Semantics(header: true, child: Text(titulo, style: tema.titleLarge))),
          ]),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Text('•  ', style: tema.bodyLarge)),
                  Expanded(child: Text(item, style: tema.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
        const AvisoOficial(),
      ],
    );
  }
}

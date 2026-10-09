/// Copia del actual.json publicado el 9/10/2026 y variantes para las pruebas.
library;

import 'dart:convert';

const actualReal = '''
{
  "generado": "2026-10-09T12:25:36-03:00",
  "cero": "Local",
  "altura_actual": {
    "valor_m": 5.95,
    "fecha": "2026-10-09T12:00:00-03:00",
    "variacion_m": 0.01,
    "periodo": "30 min",
    "estado": "crece",
    "fuente": "CARU – estación automática Paysandú",
    "url": "http://190.0.152.194:8080/alturas/web/user/estacion/19/0"
  },
  "lectura_prefectura": {
    "valor_m": 5.9,
    "fecha": "2026-10-09T06:00:00-03:00",
    "variacion_m": 0.3,
    "periodo": "24 hs",
    "estado": "crece",
    "url": "http://190.0.152.194:8080/alturas/web/user/altura/24"
  },
  "pronostico": {
    "vigente": true,
    "informe_fecha": "2026-10-08",
    "altura_esperada_m": 6.66,
    "texto": "El río continuará creciendo a niveles mayores los próximos días aguas abajo de la represa.",
    "caudal_salto_grande_m3s": 18000,
    "url_informe": "https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf"
  },
  "nivel": "alerta",
  "avisos": []
}
''';

const umbralesReal = '''
{ "validado": false, "cero": "Local", "atencion_m": null, "alerta_m": 4.39, "evacuacion_m": 6.89, "actualizado": "2026-10-09" }
''';

/// Un actual.json falso con el nivel y la altura que se pidan.
Map<String, dynamic> actualFalso(String nivel, double? valor, {List<String> avisos = const []}) {
  final j = jsonDecode(actualReal) as Map<String, dynamic>;
  j['nivel'] = nivel;
  j['avisos'] = avisos;
  if (valor == null) {
    j['altura_actual'] = null;
  } else {
    (j['altura_actual'] as Map)['valor_m'] = valor;
  }
  return j;
}

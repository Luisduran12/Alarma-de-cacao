// Genera docs/privacidad.md a partir de lib/data/politica_privacidad.dart (la única fuente).
// Uso: dart run tool/generar_privacidad.dart
import 'dart:io';

import 'package:alarmacacao5_0/data/politica_privacidad.dart';

void main() {
  final b = StringBuffer()
    ..writeln('# Política de privacidad\n')
    ..writeln('Versión breve que también se muestra dentro de la app (Ajustes > Privacidad). Responde a la Ley 1581 de '
        '2012 (protección de datos personales). Este archivo se genera con `dart run tool/generar_privacidad.dart` '
        'desde `lib/data/politica_privacidad.dart`: no lo edite a mano (una prueba comprueba que coincidan).\n');
  for (final s in PoliticaPrivacidad.secciones) {
    b.writeln('## ${s.titulo}\n');
    b.writeln('${s.texto}\n');
  }
  b
    ..writeln('## Responsable del tratamiento\n')
    ..writeln('${PoliticaPrivacidad.responsable}\nContacto: ${PoliticaPrivacidad.contacto}\n')
    ..writeln('## Lo que este documento NO es\n')
    ..writeln('${PoliticaPrivacidad.avisoLegal} Antes de publicar la app conviene que lo revise alguien con conocimiento '
        'de la Ley 1581 de 2012 (por ejemplo, para saber si hay que registrar la base de datos o definir un '
        'procedimiento de consultas y reclamos).');
  File('docs/privacidad.md').writeAsStringSync(b.toString());
}

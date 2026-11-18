/// Plantillas de ciclo de volteadas.
///
/// Las horas se cuentan desde el inicio del lote (cuando se crea).
class PlantillaCiclo {
  final String id;
  final String nombre;
  final String descripcion;

  /// Horas (desde el inicio) en que suena cada alarma de volteo.
  final List<int> horasVolteo;

  /// Duración total del ciclo en horas. Si es mayor que la última volteada,
  /// se programa una alarma final de "fin del ciclo".
  final int duracionHoras;

  /// Fuente de la pauta, para mostrarla al usuario.
  final String fuente;

  /// true si la hora final del ciclo es el final de la FERMENTACIÓN (entonces el
  /// aviso final invita a hacer la prueba de corte). En las demás plantillas el
  /// ciclo son solo alarmas y no se sabe si es el final de la fermentación.
  final bool finEsFermentacion;

  const PlantillaCiclo({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.horasVolteo,
    required this.duracionHoras,
    this.fuente = '',
    this.finEsFermentacion = false,
  });

  bool get tieneAlarmaFinal => horasVolteo.isEmpty || duracionHoras > horasVolteo.last;
}

class Plantillas {
  /// Ciclo de fermentación de 144 h (6 días).
  ///
  /// - 144 h es la duración del beneficio que reporta FEDECACAO; pasar de
  ///   144 h se considera sobrefermentación.
  /// - La pauta de volteo 48-24-24-24 (primer volteo a las 48 h, luego cada
  ///   24 h) proviene de tesis de la UIS y la UNAD sobre fermentación en
  ///   Colombia, NO de un documento oficial de FEDECACAO verificado.
  ///   FEDECACAO también ha descrito volteos cada 4 h durante los 4 días
  ///   posteriores a la fase anaeróbica. Ajuste estas horas según el
  ///   protocolo vigente de su asociación.
  static const fedecacao144 = PlantillaCiclo(
    id: 'fedecacao_144',
    nombre: 'Fermentación 144 h',
    descripcion: 'Volteos a las 48, 72, 96 y 120 h; fin de fermentación a las 144 h.',
    horasVolteo: [48, 72, 96, 120],
    duracionHoras: 144,
    fuente: 'Duración: FEDECACAO. Pauta 48-24-24-24: tesis UIS/UNAD. Verificar con el protocolo de su asociación.',
    finEsFermentacion: true,
  );

  /// Alarmas predeterminadas que ya traía la app (24, 34 y 48 h).
  static const predeterminada = PlantillaCiclo(
    id: 'predeterminada',
    nombre: 'Predeterminada (24-34-48 h)',
    descripcion: 'Las tres alarmas originales de la app.',
    horasVolteo: [24, 34, 48],
    duracionHoras: 48,
  );

  /// Plantilla con horas escritas por el usuario.
  static PlantillaCiclo personalizada(List<int> horas) {
    final ordenadas = horas.where((h) => h > 0).toSet().toList()..sort();
    return PlantillaCiclo(
      id: 'personalizada',
      nombre: 'Personalizada',
      descripcion: 'Volteos a las ${ordenadas.join(', ')} h.',
      horasVolteo: ordenadas,
      duracionHoras: ordenadas.isEmpty ? 0 : ordenadas.last,
    );
  }

  static String nombre(String? id) {
    switch (id) {
      case 'fedecacao_144':
        return fedecacao144.nombre;
      case 'predeterminada':
        return predeterminada.nombre;
      case 'personalizada':
        return 'Personalizada';
      default:
        return 'Sin plantilla';
    }
  }
}

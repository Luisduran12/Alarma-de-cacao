// models/volteada.dart

/// Etapas del beneficio del cacao.
class Etapa {
  static const fermentacion = 'fermentacion';
  static const secado = 'secado';

  static String nombre(String etapa) => etapa == secado ? 'Secado' : 'Fermentación';
}

/// Un registro del lote: una volteada programada (alarma) y, cuando se
/// confirma, los datos medidos (temperatura, humedad, observación y,
/// en secado, la ubicación del punto de secado).
///
/// Se guarda en la tabla `registros` de la base de datos.
class Volteada {
  final String id;               // ID único del registro
  final String loteId;           // ID del lote al que pertenece
  final String mensaje;          // Mensaje que acompaña la notificación
  final double temperatura;      // Temperatura registrada (°C)
  final double humedad;          // Humedad registrada (%)
  final String observacion;      // Observaciones adicionales
  final DateTime fecha;          // Fecha y hora de creación o confirmación
  final DateTime fechaProgramada; // Fecha y hora de la alarma
  final bool confirmada;         // Si la alarma ya fue atendida
  final int notifId;             // ID estable de la notificación programada (0 = ninguna)
  final String etapa;            // Etapa.fermentacion o Etapa.secado
  final double? latitud;         // Punto de secado (opcional)
  final double? longitud;

  Volteada({
    required this.id,
    required this.loteId,
    required this.mensaje,
    required this.temperatura,
    required this.humedad,
    required this.observacion,
    required this.fecha,
    required this.fechaProgramada,
    required this.confirmada,
    this.notifId = 0,
    this.etapa = Etapa.fermentacion,
    this.latitud,
    this.longitud,
  });

  bool get tieneUbicacion => latitud != null && longitud != null;

  Volteada copyWith({
    String? mensaje,
    double? temperatura,
    double? humedad,
    String? observacion,
    DateTime? fecha,
    DateTime? fechaProgramada,
    bool? confirmada,
    int? notifId,
    String? etapa,
    double? latitud,
    double? longitud,
  }) {
    return Volteada(
      id: id,
      loteId: loteId,
      mensaje: mensaje ?? this.mensaje,
      temperatura: temperatura ?? this.temperatura,
      humedad: humedad ?? this.humedad,
      observacion: observacion ?? this.observacion,
      fecha: fecha ?? this.fecha,
      fechaProgramada: fechaProgramada ?? this.fechaProgramada,
      confirmada: confirmada ?? this.confirmada,
      notifId: notifId ?? this.notifId,
      etapa: etapa ?? this.etapa,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
    );
  }

  // Serializa el objeto a JSON (exportación y migración de datos antiguos)
  Map<String, dynamic> toJson() => {
        'id': id,
        'loteId': loteId,
        'mensaje': mensaje,
        'temperatura': temperatura,
        'humedad': humedad,
        'observacion': observacion,
        'fecha': fecha.toIso8601String(),
        'fechaProgramada': fechaProgramada.toIso8601String(),
        'confirmada': confirmada,
        'notifId': notifId,
        'etapa': etapa,
        'latitud': latitud,
        'longitud': longitud,
      };

  // Crea una instancia desde JSON (tolerante a datos antiguos incompletos)
  static Volteada fromJson(Map<String, dynamic> json) {
    return Volteada(
      id: json['id'] ?? '',
      loteId: json['loteId'] ?? '',
      mensaje: json['mensaje'] ?? '',
      temperatura: (json['temperatura'] as num?)?.toDouble() ?? 0.0,
      humedad: (json['humedad'] as num?)?.toDouble() ?? 0.0,
      observacion: json['observacion'] ?? '',
      fecha: DateTime.tryParse(json['fecha'] ?? '') ?? DateTime.now(),
      fechaProgramada: DateTime.tryParse(json['fechaProgramada'] ?? '') ?? DateTime.now(),
      confirmada: json['confirmada'] ?? false,
      notifId: (json['notifId'] as num?)?.toInt() ?? 0,
      etapa: json['etapa'] ?? Etapa.fermentacion,
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
    );
  }

  /// Fila de la tabla `registros`.
  Map<String, Object?> toRow() => {
        'id': id,
        'lote_id': loteId,
        'mensaje': mensaje,
        'fecha_programada': fechaProgramada.toIso8601String(),
        'fecha': fecha.toIso8601String(),
        'temperatura': temperatura,
        'humedad': humedad,
        'observacion': observacion,
        'latitud': latitud,
        'longitud': longitud,
        'etapa': etapa,
        'confirmada': confirmada ? 1 : 0,
        'notif_id': notifId,
      };

  static Volteada fromRow(Map<String, Object?> r) {
    return Volteada(
      id: r['id'] as String,
      loteId: r['lote_id'] as String,
      mensaje: (r['mensaje'] as String?) ?? '',
      temperatura: (r['temperatura'] as num?)?.toDouble() ?? 0.0,
      humedad: (r['humedad'] as num?)?.toDouble() ?? 0.0,
      observacion: (r['observacion'] as String?) ?? '',
      fecha: DateTime.parse(r['fecha'] as String),
      fechaProgramada: DateTime.parse(r['fecha_programada'] as String),
      confirmada: (r['confirmada'] as int? ?? 0) == 1,
      notifId: (r['notif_id'] as int?) ?? 0,
      etapa: (r['etapa'] as String?) ?? Etapa.fermentacion,
      latitud: (r['latitud'] as num?)?.toDouble(),
      longitud: (r['longitud'] as num?)?.toDouble(),
    );
  }
}

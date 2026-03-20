// models/volteada.dart

class Volteada {
  final String id;               // ID único de la volteada
  final String loteId;           // ID del lote al que pertenece la volteada
  final String mensaje;          // Mensaje que acompaña la notificación
  final double temperatura;      // Temperatura registrada
  final double humedad;          // Humedad registrada
  final String observacion;      // Observaciones adicionales
  final DateTime fecha;          // Fecha y hora de creación o confirmación
  final DateTime fechaProgramada; // 📅 Fecha y hora de la alarma
  final bool confirmada;          // ✅ Si la alarma ya fue atendida

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
  });

  // Serializa el objeto a JSON
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
      };

  // Crea una instancia desde JSON
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
    );
  }
}

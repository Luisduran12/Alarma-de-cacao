/// Un aviso programado del lote que no es un registro: por ahora, "medir la
/// temperatura" cada 12 h. Se guarda para poder cancelarlo si se borra el lote
/// o se apagan los recordatorios, y para reprogramarlo si el sistema lo perdió.
class Recordatorio {
  static const medirTemperatura = 'medir_temperatura';

  final String id;
  final String loteId;
  final int notifId;
  final DateTime fechaProgramada;
  final String tipo;

  const Recordatorio({
    required this.id,
    required this.loteId,
    required this.notifId,
    required this.fechaProgramada,
    this.tipo = medirTemperatura,
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'lote_id': loteId,
        'notif_id': notifId,
        'fecha_programada': fechaProgramada.toIso8601String(),
        'tipo': tipo,
      };

  static Recordatorio fromRow(Map<String, Object?> r) => Recordatorio(
        id: r['id'] as String,
        loteId: r['lote_id'] as String,
        notifId: r['notif_id'] as int,
        fechaProgramada: DateTime.parse(r['fecha_programada'] as String),
        tipo: (r['tipo'] as String?) ?? medirTemperatura,
      );
}

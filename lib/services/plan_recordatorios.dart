import '../models/lote.dart';

/// Decide EN QUÉ MOMENTOS avisar de medir la temperatura. Solo calcula fechas
/// (no programa nada), para poder probarlo.
class PlanRecordatorios {
  PlanRecordatorios._();

  /// Cada cuántas horas se pide medir la temperatura (lo pidió el productor: 12 h).
  static const cadaHorasPorDefecto = 12;

  /// Si una alarma de volteo (o la del final) cae a menos de esta distancia de
  /// un recordatorio, ese recordatorio se omite: el formulario de la volteada ya
  /// pide la temperatura y sonarían dos avisos seguidos.
  static const margenHoras = 1.0;

  /// Fechas de los recordatorios de [lote] desde [ahora] hasta el final del ciclo:
  /// una cada [cadaHoras] contada desde el inicio del lote, sin las que coinciden
  /// con una alarma ya programada. Sin inicio o fin de ciclo no hay recordatorios.
  static List<DateTime> paraLote(Lote lote, {DateTime? ahora, int cadaHoras = cadaHorasPorDefecto}) {
    final inicio = lote.inicioCiclo, fin = lote.finCiclo;
    if (inicio == null || fin == null || cadaHoras <= 0) return [];
    final ahoraReal = ahora ?? DateTime.now();
    final duracionMin = fin.difference(inicio).inMinutes;

    // Horas del lote en que ya hay una alarma programada (volteos y final).
    final alarmas = [
      for (final v in lote.volteadas)
        if (v.notifId != 0) v.fechaProgramada.difference(inicio).inMinutes / 60.0,
    ];

    final fechas = <DateTime>[];
    for (var h = cadaHoras; h * 60 <= duracionMin; h += cadaHoras) {
      if (alarmas.any((a) => (a - h).abs() < margenHoras)) continue;
      final fecha = inicio.add(Duration(hours: h));
      if (fecha.isAfter(ahoraReal)) fechas.add(fecha);
    }
    return fechas;
  }
}

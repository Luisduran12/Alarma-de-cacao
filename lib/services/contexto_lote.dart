import '../models/lote.dart';
import '../models/volteada.dart';

/// Lo que la app le cuenta a la IA sobre el lote: etapa, horas y los últimos registros.
/// NUNCA lleva el nombre del lote ni ubicación (ni coordenadas): el servidor rechaza esos
/// campos y aquí ni siquiera se leen.
///
/// Los límites son los del servidor (`backend/src/chat.ts`): un valor fuera de rango no se
/// manda, en vez de arriesgar que todo el mensaje sea rechazado.
class ContextoLote {
  static const maxRegistros = 8;
  static const maxHoras = 3000.0;

  final String etapa;
  final double horas;
  final List<Map<String, Object>> registros;

  const ContextoLote({required this.etapa, required this.horas, required this.registros});

  factory ContextoLote.desde(Lote lote, DateTime ahora) {
    final inicio = lote.inicioCiclo ?? lote.createdAt;
    double horasDesde(DateTime t) => (t.difference(inicio).inMinutes / 60.0).clamp(0.0, maxHoras).toDouble();
    double redondear(double v) => (v * 10).roundToDouble() / 10;

    final medidos = lote.volteadas.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));

    final registros = <Map<String, Object>>[];
    for (final v in medidos) {
      if (!_dentro(v.temperatura, -10, 80) || !_dentro(v.humedad, 0, 100)) continue;
      registros.add({
        'horas': redondear(horasDesde(v.fecha)),
        'temperatura': redondear(v.temperatura),
        'humedad': redondear(v.humedad),
        if (v.ph != null && _dentro(v.ph!, 0, 14)) 'ph': redondear(v.ph!),
        if (v.brix != null && _dentro(v.brix!, 0, 100)) 'brix': redondear(v.brix!),
        if (v.tempAmbiente != null && _dentro(v.tempAmbiente!, -10, 60)) 'tempAmbiente': redondear(v.tempAmbiente!),
      });
    }

    return ContextoLote(
      etapa: medidos.isNotEmpty && medidos.last.etapa == Etapa.secado ? Etapa.secado : Etapa.fermentacion,
      horas: redondear(horasDesde(ahora)),
      registros: registros.length > maxRegistros ? registros.sublist(registros.length - maxRegistros) : registros,
    );
  }

  static bool _dentro(double v, double min, double max) => v.isFinite && v >= min && v <= max;

  Map<String, Object> toJson() => {'etapa': etapa, 'horas': horas, 'registros': registros};
}

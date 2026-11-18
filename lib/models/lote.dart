// lib/models/lote.dart
import 'package:alarmacacao5_0/models/volteada.dart';

/// Un lote de cacao en beneficio. Se guarda en la tabla `lotes`;
/// sus volteadas/registros en la tabla `registros`.
class Lote {
  final String id;
  final String title;
  final List<Volteada> volteadas;
  String status;
  final DateTime createdAt;

  /// Inicio y fin del ciclo de alarmas. Se guardan para calcular el
  /// progreso desde la hora real, aunque la app se cierre.
  final DateTime? inicioCiclo;
  final DateTime? finCiclo;

  /// 'fedecacao_144', 'predeterminada', 'personalizada' o null.
  final String? plantilla;

  Lote({
    required this.id,
    required this.title,
    this.volteadas = const [],
    required this.status,
    required this.createdAt,
    this.inicioCiclo,
    this.finCiclo,
    this.plantilla,
  });

  Lote copyWith({
    String? id,
    String? title,
    List<Volteada>? volteadas,
    String? status,
    DateTime? createdAt,
    DateTime? inicioCiclo,
    DateTime? finCiclo,
    String? plantilla,
  }) {
    return Lote(
      id: id ?? this.id,
      title: title ?? this.title,
      volteadas: volteadas ?? this.volteadas,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      inicioCiclo: inicioCiclo ?? this.inicioCiclo,
      finCiclo: finCiclo ?? this.finCiclo,
      plantilla: plantilla ?? this.plantilla,
    );
  }

  /// Progreso del ciclo (0.0 a 1.0) calculado desde la hora de inicio
  /// guardada. No depende de timers en memoria.
  double progreso([DateTime? ahora]) {
    final inicio = inicioCiclo, fin = finCiclo;
    if (inicio == null || fin == null) return 0.0;
    final total = fin.difference(inicio).inSeconds;
    if (total <= 0) return 1.0;
    final transcurrido = (ahora ?? DateTime.now()).difference(inicio).inSeconds;
    return (transcurrido / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'volteadas': volteadas.map((v) => v.toJson()).toList(),
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'inicioCiclo': inicioCiclo?.toIso8601String(),
      'finCiclo': finCiclo?.toIso8601String(),
      'plantilla': plantilla,
    };
  }

  factory Lote.fromJson(Map<String, dynamic> json) {
    return Lote(
      id: json['id'],
      title: json['title'] ?? 'Lote sin nombre',
      volteadas: ((json['volteadas'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Volteada.fromJson)
          .toList(),
      status: json['status'] ?? 'en proceso',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      inicioCiclo: DateTime.tryParse(json['inicioCiclo'] ?? ''),
      finCiclo: DateTime.tryParse(json['finCiclo'] ?? ''),
      plantilla: json['plantilla'],
    );
  }

  /// Fila de la tabla `lotes` (sin las volteadas).
  Map<String, Object?> toRow() => {
        'id': id,
        'titulo': title,
        'estado': status,
        'creado_en': createdAt.toIso8601String(),
        'inicio_ciclo': inicioCiclo?.toIso8601String(),
        'fin_ciclo': finCiclo?.toIso8601String(),
        'plantilla': plantilla,
      };

  static Lote fromRow(Map<String, Object?> r, List<Volteada> volteadas) {
    return Lote(
      id: r['id'] as String,
      title: r['titulo'] as String,
      status: r['estado'] as String,
      createdAt: DateTime.parse(r['creado_en'] as String),
      inicioCiclo: DateTime.tryParse((r['inicio_ciclo'] as String?) ?? ''),
      finCiclo: DateTime.tryParse((r['fin_ciclo'] as String?) ?? ''),
      plantilla: r['plantilla'] as String?,
      volteadas: volteadas,
    );
  }
}

// lib/models/lote.dart
import 'package:alarmacacao5_0/models/volteada.dart';

/// Calidad del grano al terminar el beneficio.
class Calidad {
  static const excelente = 'excelente';
  static const buena = 'buena';
  static const regular = 'regular';
  static const mala = 'mala';

  static const todas = [excelente, buena, regular, mala];

  static String nombre(String? c) => switch (c) {
        excelente => 'Excelente',
        buena => 'Buena',
        regular => 'Regular',
        mala => 'Mala',
        _ => 'Sin evaluar',
      };

  /// Orden para comparar: menor = mejor. Sin evaluar va al final.
  static int rango(String? c) {
    final i = todas.indexOf(c ?? '');
    return i == -1 ? todas.length : i;
  }
}

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

  /// Resultado del grano al terminar (ver [Calidad]) y su observación
  /// (por ejemplo, la prueba de corte). Se usan para comparar lotes.
  final String? calidadResultado;
  final String? observacionResultado;

  Lote({
    required this.id,
    required this.title,
    this.volteadas = const [],
    required this.status,
    required this.createdAt,
    this.inicioCiclo,
    this.finCiclo,
    this.plantilla,
    this.calidadResultado,
    this.observacionResultado,
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
    String? calidadResultado,
    String? observacionResultado,
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
      calidadResultado: calidadResultado ?? this.calidadResultado,
      observacionResultado: observacionResultado ?? this.observacionResultado,
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
      'calidadResultado': calidadResultado,
      'observacionResultado': observacionResultado,
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
      calidadResultado: json['calidadResultado'],
      observacionResultado: json['observacionResultado'],
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
        'calidad_resultado': calidadResultado,
        'observacion_resultado': observacionResultado,
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
      calidadResultado: r['calidad_resultado'] as String?,
      observacionResultado: r['observacion_resultado'] as String?,
      volteadas: volteadas,
    );
  }
}

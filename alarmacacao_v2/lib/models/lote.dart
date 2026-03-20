// lib/models/lote.dart
import 'package:alarmacacao5_0/models/volteada.dart';

class Lote {
  final String id;
  final String title;
  final List<Volteada> volteadas; // Ahora guarda objetos Volteada
  String status;
  final DateTime createdAt;

  Lote({
    required this.id,
    required this.title,
    this.volteadas = const [],
    required this.status,
    required this.createdAt,
  });

  Lote copyWith({
    String? id,
    String? title,
    List<Volteada>? volteadas,
    String? status,
    DateTime? createdAt,
  }) {
    return Lote(
      id: id ?? this.id,
      title: title ?? this.title,
      volteadas: volteadas ?? this.volteadas,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'volteadas': volteadas.map((v) => v.toJson()).toList(),
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Lote.fromJson(Map<String, dynamic> json) {
    return Lote(
      id: json['id'],
      title: json['title'],
      volteadas: (json['volteadas'] as List<dynamic>)
          .map((v) => Volteada.fromJson(v))
          .toList(),
      status: json['status'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

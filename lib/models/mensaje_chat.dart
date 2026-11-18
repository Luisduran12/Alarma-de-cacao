import 'dart:convert';

enum RolChat { usuario, asistente }

/// De dónde salió un mensaje: de la IA (con internet), de la base de conocimiento del teléfono,
/// o un aviso de la propia app (por ejemplo, "sin conexión").
enum OrigenMensaje { ia, local, sistema }

class FuenteCitada {
  final String id;
  final String fuente;
  const FuenteCitada(this.id, this.fuente);

  Map<String, String> toJson() => {'id': id, 'fuente': fuente};
}

/// Un mensaje de la conversación de un lote.
class MensajeChat {
  final int? id;
  final String loteId;
  final RolChat rol;
  final String texto;
  final OrigenMensaje origen;
  final List<FuenteCitada> fuentes;
  final DateTime creadoEn;

  const MensajeChat({
    this.id,
    required this.loteId,
    required this.rol,
    required this.texto,
    this.origen = OrigenMensaje.ia,
    this.fuentes = const [],
    required this.creadoEn,
  });

  Map<String, Object?> toRow() => {
        'lote_id': loteId,
        'rol': rol.name,
        'texto': texto,
        'origen': origen.name,
        'fuentes': jsonEncode([for (final f in fuentes) f.toJson()]),
        'creado_en': creadoEn.toUtc().toIso8601String(),
      };

  /// Lee una fila; si algo está dañado usa valores seguros en vez de fallar.
  factory MensajeChat.desdeFila(Map<String, Object?> f) {
    List<FuenteCitada> fuentes = const [];
    try {
      final j = jsonDecode((f['fuentes'] as String?) ?? '[]');
      if (j is List) {
        fuentes = [
          for (final x in j)
            if (x is Map && x['id'] is String && x['fuente'] is String) FuenteCitada(x['id'] as String, x['fuente'] as String)
        ];
      }
    } catch (_) {}
    return MensajeChat(
      id: f['id'] as int?,
      loteId: f['lote_id'] as String,
      rol: RolChat.values.firstWhere((r) => r.name == f['rol'], orElse: () => RolChat.asistente),
      texto: (f['texto'] as String?) ?? '',
      origen: OrigenMensaje.values.firstWhere((o) => o.name == f['origen'], orElse: () => OrigenMensaje.sistema),
      fuentes: fuentes,
      creadoEn: DateTime.tryParse((f['creado_en'] as String?) ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

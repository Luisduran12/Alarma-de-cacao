import 'package:sqflite/sqflite.dart';

import '../data/cacao_database.dart';
import '../models/mensaje_chat.dart';

/// Historial del chat de cada lote. Vive solo en el teléfono (tabla `chat_mensajes`) y se
/// borra con el lote.
class ChatHistorial {
  /// Lo máximo que acepta el servidor por turno (`historial[].texto`).
  static const maxTextoServidor = 800;
  static const maxTurnosServidor = 6;

  final Future<Database> Function() _db;
  final DateTime Function() _ahora;

  ChatHistorial({Future<Database> Function()? database, DateTime Function()? ahora})
      : _db = database ?? CacaoDatabase.instancia,
        _ahora = ahora ?? DateTime.now;

  Future<MensajeChat> agregar(
    String loteId,
    RolChat rol,
    String texto, {
    OrigenMensaje origen = OrigenMensaje.ia,
    List<FuenteCitada> fuentes = const [],
  }) async {
    final m = MensajeChat(loteId: loteId, rol: rol, texto: texto, origen: origen, fuentes: fuentes, creadoEn: _ahora());
    final id = await (await _db()).insert('chat_mensajes', m.toRow());
    return MensajeChat(id: id, loteId: loteId, rol: rol, texto: texto, origen: origen, fuentes: fuentes, creadoEn: m.creadoEn);
  }

  /// Los mensajes del lote, del más viejo al más nuevo. Con [limite] devuelve los últimos.
  Future<List<MensajeChat>> listar(String loteId, {int? limite}) async {
    final filas = await (await _db()).query(
      'chat_mensajes',
      where: 'lote_id = ?',
      whereArgs: [loteId],
      orderBy: 'id DESC',
      limit: limite,
    );
    return filas.reversed.map(MensajeChat.desdeFila).toList();
  }

  /// Los últimos turnos en el formato del servidor (`historial`): sin avisos de la app y con
  /// el texto recortado al máximo permitido.
  Future<List<Map<String, String>>> paraServidor(String loteId, {int maximo = maxTurnosServidor}) async {
    final filas = await (await _db()).query(
      'chat_mensajes',
      where: "lote_id = ? AND origen != 'sistema'",
      whereArgs: [loteId],
      orderBy: 'id DESC',
      limit: maximo,
    );
    return [
      for (final m in filas.reversed.map(MensajeChat.desdeFila))
        if (m.texto.trim().isNotEmpty)
          {
            'rol': m.rol.name,
            'texto': m.texto.length > maxTextoServidor ? m.texto.substring(0, maxTextoServidor) : m.texto,
          }
    ];
  }

  Future<int> borrar(String loteId) async =>
      (await _db()).delete('chat_mensajes', where: 'lote_id = ?', whereArgs: [loteId]);
}

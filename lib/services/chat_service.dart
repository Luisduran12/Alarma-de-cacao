import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/base_conocimiento.dart';
import '../models/mensaje_chat.dart';
import 'contexto_lote.dart';
import 'instalacion_id.dart';

/// Aviso fijo que la app muestra siempre junto a las respuestas del chat.
const avisoGuia = 'Es una guía, no reemplaza al técnico.';

/// La respuesta de la IA ya lista para mostrar.
class RespuestaChat {
  final String texto;

  /// Solo los fragmentos que la IA citó y que la app sí había enviado, con su id REAL de la
  /// base de conocimiento (no el "F1" temporal del mensaje).
  final List<FuenteCitada> fuentes;

  /// true si la IA se quedó sin espacio y la respuesta quedó cortada.
  final bool truncada;
  const RespuestaChat(this.texto, this.fuentes, this.truncada);
}

/// Por qué no se pudo consultar a la IA. [mensaje] está escrito para el productor.
class ChatException implements Exception {
  /// `sin_servidor`, `sin_conexion`, `respuesta_invalida` o el código que devolvió el servidor
  /// (`limite_dia`, `presupuesto_agotado`, `ia_ocupada`...).
  final String codigo;
  final String mensaje;
  final Duration? reintentarEn;
  const ChatException(this.codigo, this.mensaje, {this.reintentarEn});

  /// Cuando conviene contestar con la base local en vez de mostrar solo el error.
  bool get usarRespuestaLocal => true;

  @override
  String toString() => 'ChatException($codigo)';
}

/// Cliente del endpoint `POST {BACKEND_URL}/chat` (ver `backend/README.md`).
///
/// Manda la pregunta, el contexto del lote (sin nombre ni ubicación), hasta 6 turnos
/// anteriores y hasta 5 fragmentos de la base de conocimiento del teléfono. El servidor no
/// guarda nada de eso.
class ChatService {
  static const urlPorDefecto = String.fromEnvironment('BACKEND_URL');
  static const _maxMensaje = 500;
  static const _maxRespuesta = 6000;
  static const _maxMensajeError = 300;

  final http.Client _cliente;
  final Uri? _servidor;
  final Duration _timeout;
  final Future<String> Function() _idInstalacion;

  ChatService({http.Client? cliente, String? urlServidor, Duration? timeout, Future<String> Function()? idInstalacion})
      : _cliente = cliente ?? http.Client(),
        _servidor = _leerUrl(urlServidor ?? urlPorDefecto),
        _timeout = timeout ?? const Duration(seconds: 40),
        _idInstalacion = idInstalacion ?? InstalacionId.obtener;

  static Uri? _leerUrl(String t) {
    if (t.trim().isEmpty) return null;
    final u = Uri.tryParse(t.trim());
    return (u != null && u.hasScheme && u.host.isNotEmpty) ? u : null;
  }

  bool get servidorConfigurado => _servidor != null;

  /// El cuerpo exacto que se envía. Público para poder probar que no lleva datos de más.
  /// A los fragmentos se les pone un id corto (F1, F2…) porque así los cita la IA.
  static Map<String, Object> armarCuerpo({
    required String mensaje,
    ContextoLote? contexto,
    List<Map<String, String>> historial = const [],
    List<Fragmento> fragmentos = const [],
  }) {
    final texto = mensaje.trim();
    final cuerpo = <String, Object>{
      'mensaje': texto.length > _maxMensaje ? texto.substring(0, _maxMensaje) : texto,
    };
    if (contexto != null) cuerpo['contexto'] = contexto.toJson();
    if (historial.isNotEmpty) {
      cuerpo['historial'] = historial.length > 6 ? historial.sublist(historial.length - 6) : historial;
    }
    final usados = fragmentos.take(LimitesServidor.maxFragmentos).toList();
    if (usados.isNotEmpty) {
      cuerpo['fragmentos'] = [
        for (var i = 0; i < usados.length; i++)
          {
            'id': 'F${i + 1}',
            'fuente': _recortar(usados[i].fuente, LimitesServidor.maxFuente),
            'texto': _recortar(usados[i].texto, LimitesServidor.maxTexto),
          }
      ];
    }
    return cuerpo;
  }

  static String _recortar(String t, int max) => t.length > max ? t.substring(0, max) : t;

  Future<RespuestaChat> preguntar({
    required String mensaje,
    ContextoLote? contexto,
    List<Map<String, String>> historial = const [],
    List<Fragmento> fragmentos = const [],
  }) async {
    final base = _servidor;
    if (base == null) {
      throw const ChatException('sin_servidor', 'La IA no está disponible en esta versión de la app.');
    }
    if (mensaje.trim().isEmpty) throw ArgumentError('El mensaje no puede estar vacío');

    final cuerpo = armarCuerpo(mensaje: mensaje, contexto: contexto, historial: historial, fragmentos: fragmentos);
    final ruta = '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/chat';

    http.Response r;
    try {
      r = await _cliente
          .post(base.replace(path: ruta),
              headers: {'Content-Type': 'application/json', 'X-Install-Id': await _idInstalacion()},
              body: jsonEncode(cuerpo))
          .timeout(_timeout);
    } on TimeoutException {
      throw const ChatException('sin_conexion', 'La consulta tardó demasiado. Revise su señal e intente de nuevo.');
    } on SocketException {
      throw const ChatException('sin_conexion', 'No hay conexión a internet.');
    } on http.ClientException {
      throw const ChatException('sin_conexion', 'No hay conexión a internet.');
    }

    final j = _decodificar(r);
    if (r.statusCode != 200) throw _errorDe(r, j);

    final texto = j is Map ? j['respuesta'] : null;
    if (texto is! String || texto.trim().isEmpty || texto.length > _maxRespuesta) {
      throw const ChatException('respuesta_invalida', 'La IA respondió algo que no se pudo entender. Intente de nuevo.');
    }

    final enviados = {
      for (var i = 0; i < (cuerpo['fragmentos'] as List? ?? const []).length; i++)
        'F${i + 1}': fragmentos[i],
    };
    final fuentes = <FuenteCitada>[];
    final crudas = j['fuentes'];
    if (crudas is List) {
      for (final f in crudas) {
        final real = f is Map && f['id'] is String ? enviados[f['id']] : null;
        if (real != null && !fuentes.any((x) => x.id == real.id)) fuentes.add(FuenteCitada(real.id, real.fuente));
      }
    }
    return RespuestaChat(texto.trim(), fuentes, j['truncada'] == true);
  }

  dynamic _decodificar(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  ChatException _errorDe(http.Response r, dynamic j) {
    final e = j is Map ? j['error'] : null;
    final codigo = e is Map && e['codigo'] is String ? e['codigo'] as String : 'error_${r.statusCode}';
    var mensaje = e is Map && e['mensaje'] is String ? (e['mensaje'] as String).trim() : '';
    if (mensaje.isEmpty) mensaje = 'No se pudo consultar a la IA ahora. Intente más tarde.';
    if (mensaje.length > _maxMensajeError) mensaje = mensaje.substring(0, _maxMensajeError);
    final seg = int.tryParse(r.headers['retry-after'] ?? '');
    return ChatException(codigo, mensaje, reintentarEn: seg != null && seg > 0 ? Duration(seconds: seg) : null);
  }
}

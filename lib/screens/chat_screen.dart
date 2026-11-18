import 'package:flutter/material.dart';

import '../models/lote.dart';
import '../models/mensaje_chat.dart';
import '../services/chat_historial.dart';
import '../services/chat_service.dart';
import '../services/contexto_lote.dart';
import '../services/lote_service.dart';
import '../services/respuestas_locales.dart';
import '../data/base_conocimiento.dart';

/// Chat de preguntas sobre un lote.
///
/// Con internet pregunta a la IA (con el contexto del lote y fragmentos de la base de
/// conocimiento del teléfono, para que cite la fuente). Sin internet, o si la IA falla,
/// responde con la guía guardada en el teléfono y lo avisa. El historial es de cada lote y
/// solo vive en el teléfono.
class ChatScreen extends StatefulWidget {
  final Lote lote;

  /// Se pueden cambiar en pruebas.
  final LoteService? loteService;
  final ChatHistorial? historial;
  final ChatService? chat;
  final RespuestasLocales? respuestas;
  final DateTime Function()? ahora;

  const ChatScreen({super.key, required this.lote, this.loteService, this.historial, this.chat, this.respuestas, this.ahora});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final LoteService _lotes = widget.loteService ?? LoteService();
  late final ChatHistorial _historial = widget.historial ?? ChatHistorial();
  late final ChatService _chat = widget.chat ?? ChatService();
  final _texto = TextEditingController();
  final _scroll = ScrollController();

  RespuestasLocales? _local;
  List<MensajeChat> _mensajes = [];
  bool _cargando = true;
  bool _pensando = false;
  bool _rapidasAbiertas = true;

  DateTime _ahora() => (widget.ahora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final local = widget.respuestas ?? RespuestasLocales(await BaseConocimiento.cargar());
    final m = await _historial.listar(widget.lote.id);
    if (!mounted) return;
    setState(() {
      _local = local;
      _mensajes = m;
      _rapidasAbiertas = m.isEmpty;
      _cargando = false;
    });
    _alFinal();
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _agregar(RolChat rol, String texto, {OrigenMensaje origen = OrigenMensaje.ia, List<FuenteCitada> fuentes = const []}) async {
    final m = await _historial.agregar(widget.lote.id, rol, texto, origen: origen, fuentes: fuentes);
    if (!mounted) return;
    setState(() => _mensajes = [..._mensajes, m]);
    _alFinal();
  }

  static final _marcas = RegExp(r'\s*\[F\d+\]');

  Future<void> _enviar(String pregunta) async {
    final p = pregunta.trim();
    final local = _local;
    if (p.isEmpty || _pensando || local == null) return;
    _texto.clear();
    setState(() {
      _pensando = true;
      _rapidasAbiertas = false;
    });
    try {
      final previo = await _historial.paraServidor(widget.lote.id);
      await _agregar(RolChat.usuario, p);
      final lote = await _lotes.obtenerLotePorId(widget.lote.id) ?? widget.lote;

      if (_chat.servidorConfigurado) {
        try {
          final contexto = ContextoLote.desde(lote, _ahora());
          final fragmentos = local.buscador.buscar(p, etapa: contexto.etapa, limite: 4);
          final r = await _chat.preguntar(mensaje: p, contexto: contexto, historial: previo, fragmentos: fragmentos);
          final limpio = r.texto.replaceAll(_marcas, '').trim();
          await _agregar(RolChat.asistente, r.truncada ? '$limpio…' : limpio, fuentes: r.fuentes);
          return;
        } on ChatException catch (e) {
          await _agregar(RolChat.asistente, e.mensaje, origen: OrigenMensaje.sistema);
        }
      }

      final l = local.responder(p, lote: lote, ahora: _ahora());
      await _agregar(RolChat.asistente, l.texto, origen: OrigenMensaje.local, fuentes: l.fuentes);
    } finally {
      if (mounted) setState(() => _pensando = false);
    }
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar la conversación?'),
        content: const Text('Se borran las preguntas y respuestas de este lote. Los registros del lote no se tocan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _historial.borrar(widget.lote.id);
    if (mounted) setState(() => _mensajes = []);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preguntar sobre el lote'),
        actions: [
          if (_mensajes.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Borrar la conversación', onPressed: _borrar),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: tema.colorScheme.secondaryContainer,
            padding: const EdgeInsets.all(12),
            child: Text(
              avisoGuia,
              key: const Key('aviso_guia'),
              style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: tema.colorScheme.onSecondaryContainer),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _mensajes.isEmpty
                    ? _vacio(tema)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _mensajes.length + (_pensando ? 1 : 0),
                        itemBuilder: (_, i) => i == _mensajes.length ? _pensandoFila(tema) : _Burbuja(_mensajes[i]),
                      ),
          ),
          _botonesRapidos(),
          _entrada(tema),
        ],
      ),
    );
  }

  Widget _vacio(ThemeData tema) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.forum_outlined, size: 48, color: tema.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Pregunte sobre su lote de cacao', style: tema.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Toque una pregunta de abajo o escriba la suya.\n\n'
            'Con internet le responde una IA con el material guardado en la app y le dice de dónde sale. '
            'Se envían su pregunta y las medidas del lote (sin el nombre del lote ni su ubicación).\n\n'
            'Sin internet le responde la guía guardada en el teléfono.',
            style: tema.textTheme.bodyLarge,
          ),
        ],
      );

  Widget _pensandoFila(ThemeData tema) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Pensando…', style: tema.textTheme.bodyLarge),
        ]),
      );

  /// Todos los botones a la vista (nada escondido en un deslizamiento); se pliegan para dejar
  /// sitio a la conversación.
  Widget _botonesRapidos() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _rapidasAbiertas = !_rapidasAbiertas),
            icon: Icon(_rapidasAbiertas ? Icons.expand_more : Icons.expand_less),
            label: const Text('Preguntas rápidas'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
          if (_rapidasAbiertas)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in PreguntaRapida.todas)
                      OutlinedButton(
                        onPressed: _pensando || _cargando ? null : () => _enviar(r.etiqueta),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: Text(r.etiqueta),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );

  Widget _entrada(ThemeData tema) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _texto,
                  enabled: !_pensando && !_cargando,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _enviar,
                  decoration: const InputDecoration(labelText: 'Escriba su pregunta', border: OutlineInputBorder()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: IconButton.filled(
                  onPressed: _pensando || _cargando ? null : () => _enviar(_texto.text),
                  icon: const Icon(Icons.send),
                  tooltip: 'Enviar pregunta',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Burbuja extends StatelessWidget {
  final MensajeChat m;
  const _Burbuja(this.m);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = tema.colorScheme;
    final propio = m.rol == RolChat.usuario;
    final sistema = m.origen == OrigenMensaje.sistema;

    final fondo = propio ? c.primaryContainer : (sistema ? c.errorContainer : c.surfaceContainerHighest);
    final color = propio ? c.onPrimaryContainer : (sistema ? c.onErrorContainer : c.onSurface);
    final quien = propio ? 'Usted' : (sistema ? 'Aviso' : (m.origen == OrigenMensaje.local ? 'Guía del teléfono' : 'IA'));

    return Align(
      alignment: propio ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        container: true,
        label: '$quien: ${m.texto}',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
          decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(quien, style: tema.textTheme.labelLarge?.copyWith(color: color)),
              const SizedBox(height: 2),
              SelectableText(m.texto, style: tema.textTheme.bodyLarge?.copyWith(color: color)),
              if (m.origen == OrigenMensaje.ia && m.fuentes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Fuentes:', style: tema.textTheme.labelLarge?.copyWith(color: color)),
                for (final f in m.fuentes) Text('• ${f.fuente}', style: tema.textTheme.bodyMedium?.copyWith(color: color)),
              ],
              if (m.origen == OrigenMensaje.local) ...[
                const SizedBox(height: 8),
                Text(RespuestasLocales.avisoSinIA, style: tema.textTheme.bodyMedium?.copyWith(color: color, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

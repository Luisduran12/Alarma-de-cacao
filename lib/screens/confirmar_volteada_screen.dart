import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/lugar_service.dart';
import 'package:alarmacacao5_0/widgets/lugar_texto.dart';
import 'package:alarmacacao5_0/services/notification_ids.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/reglas_alerta.dart';

/// Formulario de registro de una volteada (se abre al tocar la alarma) o de
/// un registro nuevo del lote (por ejemplo, durante el secado).
///
/// Guarda temperatura, humedad, observación, etapa y, en secado, la
/// latitud/longitud del punto de secado.
class ConfirmarVolteadaScreen extends StatefulWidget {
  final String loteId;

  /// Registro programado a confirmar. Vacío = registro nuevo.
  final String volteadaId;

  /// Solo para alarmas antiguas sin volteadaId.
  final String mensaje;

  /// Se pueden cambiar en pruebas; por defecto usan la base de datos, las reglas
  /// guardadas en el teléfono y una notificación local (todo sin internet).
  final LoteService? loteService;
  final LocationService? ubicacion;
  final LugarService? lugarService;
  final Future<List<ReglaAlerta>> Function()? cargarReglas;
  final Future<void> Function(String titulo, String cuerpo)? notificarAlerta;

  const ConfirmarVolteadaScreen({
    super.key,
    required this.loteId,
    this.volteadaId = '',
    this.mensaje = '',
    this.loteService,
    this.ubicacion,
    this.lugarService,
    this.cargarReglas,
    this.notificarAlerta,
  });

  @override
  State<ConfirmarVolteadaScreen> createState() => _ConfirmarVolteadaScreenState();
}

class _ConfirmarVolteadaScreenState extends State<ConfirmarVolteadaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _observacionController = TextEditingController();
  final _phController = TextEditingController();
  final _brixController = TextEditingController();
  final _tempAmbienteController = TextEditingController();
  late final LoteService _loteService = widget.loteService ?? LoteService();

  Lote? _lote;
  Volteada? _base; // registro programado que se está confirmando
  bool _cargando = true;
  bool _guardando = false;

  String _etapa = Etapa.fermentacion;
  double? _latitud;
  double? _longitud;
  bool _buscandoUbicacion = false;
  String? _errorUbicacion;
  bool _errorEsDePermiso = false; // el arreglo es abrir los ajustes del teléfono
  UbicacionObtenida? _ultimaUbicacion; // para mostrar precisión y antigüedad

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tempController.dispose();
    _humedadController.dispose();
    _observacionController.dispose();
    _phController.dispose();
    _brixController.dispose();
    _tempAmbienteController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final lote = await _loteService.obtenerLotePorId(widget.loteId);
    Volteada? base;
    if (lote != null) {
      if (widget.volteadaId.isNotEmpty) {
        base = lote.volteadas.where((v) => v.id == widget.volteadaId).firstOrNull;
      } else if (widget.mensaje.isNotEmpty) {
        base = lote.volteadas.where((v) => v.mensaje == widget.mensaje && !v.confirmada).firstOrNull;
      }
    }
    if (!mounted) return;
    setState(() {
      _lote = lote;
      _base = base;
      _cargando = false;
      if (base != null && base.confirmada) {
        // Ya estaba registrada: se muestran sus datos para corregirlos.
        _tempController.text = base.temperatura.toString();
        _humedadController.text = base.humedad.toString();
        _observacionController.text = base.observacion;
        _phController.text = base.ph?.toString() ?? '';
        _brixController.text = base.brix?.toString() ?? '';
        _tempAmbienteController.text = base.tempAmbiente?.toString() ?? '';
        _etapa = base.etapa;
        _latitud = base.latitud;
        _longitud = base.longitud;
      } else if (lote?.finCiclo != null && DateTime.now().isAfter(lote!.finCiclo!)) {
        // Si la fermentación ya terminó, lo normal es registrar el secado.
        _etapa = Etapa.secado;
      }
    });
    if (_etapa == Etapa.secado && _latitud == null) _capturarUbicacion();
  }

  Future<void> _capturarUbicacion() async {
    setState(() {
      _buscandoUbicacion = true;
      _errorUbicacion = null;
      _errorEsDePermiso = false;
    });
    try {
      final pos = await (widget.ubicacion ?? LocationService()).obtener();
      if (!mounted) return;
      setState(() {
        _latitud = pos.latitud;
        _longitud = pos.longitud;
        _ultimaUbicacion = pos;
      });
    } on UbicacionException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorUbicacion = e.mensaje;
        _errorEsDePermiso = e.abrirAjustes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorUbicacion = 'No se pudo obtener la ubicación.');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final lote = _lote;
    if (lote == null) return;

    setState(() => _guardando = true);
    final ahora = DateTime.now();
    final esSecado = _etapa == Etapa.secado;

    final registro = Volteada(
      id: _base?.id ?? const Uuid().v4(),
      loteId: lote.id,
      mensaje: _base?.mensaje ?? (esSecado ? 'Registro de secado' : 'Registro de fermentación'),
      temperatura: double.parse(_tempController.text.trim().replaceAll(',', '.')),
      humedad: double.parse(_humedadController.text.trim().replaceAll(',', '.')),
      observacion: _observacionController.text.trim(),
      fecha: ahora,
      fechaProgramada: _base?.fechaProgramada ?? ahora,
      confirmada: true,
      notifId: _base?.notifId ?? 0,
      etapa: _etapa,
      latitud: esSecado ? _latitud : null,
      longitud: esSecado ? _longitud : null,
      ph: _numeroOpcional(_phController.text),
      brix: _numeroOpcional(_brixController.text),
      tempAmbiente: _numeroOpcional(_tempAmbienteController.text),
    );

    // Se actualiza el registro existente (no se duplica) o se agrega uno nuevo.
    await _loteService.guardarRegistro(registro);

    final registros = await _loteService.obtenerRegistrosDelLote(lote.id);
    final completado = registros.isNotEmpty && registros.every((v) => v.confirmada);
    if (completado && lote.status != 'completado') {
      await _loteService.actualizarEstado(lote.id, 'completado');
    }

    await _avisarAlertas(lote, registro, ahora);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(completado ? '🎉 Todas las volteadas registradas' : '✅ Registro guardado')),
    );
    Navigator.pop(context, true);
  }

  /// Compara el registro con las reglas de alerta y, si algún valor sale de
  /// rango, avisa con una notificación local y con un cuadro en pantalla.
  /// Nada de esto necesita internet. Un fallo aquí nunca impide guardar el registro.
  Future<void> _avisarAlertas(Lote lote, Volteada registro, DateTime ahora) async {
    List<AlertaDisparada> alertas;
    try {
      final reglas = await (widget.cargarReglas ?? ReglasAlertaStorage.cargar)();
      final inicio = lote.inicioCiclo ?? lote.createdAt;
      alertas = EvaluadorAlertas.evaluar(registro, ahora.difference(inicio).inMinutes / 60.0, reglas);
    } catch (e) {
      debugPrint('No se pudieron evaluar las alertas: $e');
      return;
    }
    if (alertas.isEmpty) return;

    final titulo = 'Alerta - ${lote.title}';
    final cuerpo = alertas.map((a) => a.texto).join('\n');
    try {
      await (widget.notificarAlerta ?? _notificarLocal)(titulo, cuerpo);
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación de alerta: $e');
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 40),
        title: Text(alertas.length == 1 ? 'Atención: un valor fuera de rango' : 'Atención: ${alertas.length} valores fuera de rango'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in alertas) ...[
                Text(a.texto, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text('Fuente: ${a.regla.fuente}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
              ],
              const Text('Es una guía, no reemplaza al técnico.'),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  static Future<void> _notificarLocal(String titulo, String cuerpo) async {
    await NotificationService().mostrarNotificacion(
      id: await NotificationIds.siguiente(),
      titulo: titulo,
      cuerpo: cuerpo,
    );
  }

  /// Vacío = null (el campo es opcional). Acepta coma decimal.
  static double? _numeroOpcional(String texto) {
    final t = texto.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  String? _validarOpcional(String? val, double min, double max) {
    if (val == null || val.trim().isEmpty) return null;
    final n = double.tryParse(val.trim().replaceAll(',', '.'));
    if (n == null) return 'Valor inválido';
    if (n < min || n > max) return 'Debe estar entre ${min.toInt()} y ${max.toInt()}';
    return null;
  }

  String? _validarNumero(String? val, String nombre, double min, double max) {
    if (val == null || val.trim().isEmpty) return 'Ingrese la $nombre';
    final n = double.tryParse(val.trim().replaceAll(',', '.'));
    if (n == null) return 'Valor inválido';
    if (n < min || n > max) return 'Debe estar entre ${min.toInt()} y ${max.toInt()}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_base != null ? 'Confirmar volteada' : 'Nuevo registro')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _lote == null
              ? const Center(child: Text('No se encontró el lote de este registro.'))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Lote: ${_lote!.title}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (_base != null) Text('Alarma: ${_base!.mensaje}'),
                      const SizedBox(height: 20),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: Etapa.fermentacion, label: Text('Fermentación'), icon: Icon(Icons.science)),
                          ButtonSegment(value: Etapa.secado, label: Text('Secado'), icon: Icon(Icons.wb_sunny)),
                        ],
                        selected: {_etapa},
                        onSelectionChanged: (s) {
                          setState(() => _etapa = s.first);
                          if (_etapa == Etapa.secado && _latitud == null) _capturarUbicacion();
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _tempController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Temperatura de la masa (°C)', border: OutlineInputBorder()),
                        validator: (v) => _validarNumero(v, 'temperatura', -10, 80),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _humedadController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Humedad (%)', border: OutlineInputBorder()),
                        validator: (v) => _validarNumero(v, 'humedad', 0, 100),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'pH (opcional)', border: OutlineInputBorder()),
                        validator: (v) => _validarOpcional(v, 0, 14),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _brixController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '°Brix (opcional)', border: OutlineInputBorder()),
                        validator: (v) => _validarOpcional(v, 0, 100),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tempAmbienteController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Temperatura ambiente (°C, opcional)',
                          helperText: 'La del aire del lugar, no la de la masa de cacao.',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => _validarOpcional(v, -10, 60),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _observacionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Observación',
                          hintText: 'Olor, color, aspecto del grano…',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Ingrese una observación' : null,
                      ),
                      if (_etapa == Etapa.secado) ...[
                        const SizedBox(height: 16),
                        _buildUbicacion(),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_guardando ? 'Guardando...' : 'Guardar datos'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// Precisión, y aviso si la posición no es nueva (puede ser de otro lugar).
  List<Widget> _detalleUbicacion() {
    final u = _ultimaUbicacion;
    if (u == null) return const []; // ubicación que ya venía guardada en el registro
    return [
      if (u.precisionMetros != null) Text('Precisión: unos ${u.precisionMetros!.round()} m'),
      if (u.esUltimaConocida)
        Text(
          'Es la última ubicación que tenía el teléfono${u.hace(DateTime.now()) == null ? '' : ' (${u.hace(DateTime.now())})'}: '
          'puede no ser de este lugar. Salga a un sitio abierto y toque "Actualizar ubicación".',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ];
  }

  Widget _buildUbicacion() {
    final tiene = _latitud != null && _longitud != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Punto de secado', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (_buscandoUbicacion)
              const Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Obteniendo ubicación GPS…'),
              ])
            else if (tiene) ...[
              Text('Lat ${_latitud!.toStringAsFixed(6)}, Lon ${_longitud!.toStringAsFixed(6)}'),
              LugarTexto(latitud: _latitud!, longitud: _longitud!, servicio: widget.lugarService),
              ..._detalleUbicacion(),
            ] else
              Text(_errorUbicacion ?? 'Sin ubicación. Se puede guardar sin ella.',
                  style: TextStyle(color: _errorUbicacion != null ? Colors.red : null)),
            if (_errorEsDePermiso && !tiene)
              TextButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Abrir ajustes'),
              ),
            TextButton.icon(
              onPressed: _buscandoUbicacion ? null : _capturarUbicacion,
              icon: const Icon(Icons.my_location),
              label: Text(tiene ? 'Actualizar ubicación' : 'Capturar ubicación'),
            ),
          ],
        ),
      ),
    );
  }
}

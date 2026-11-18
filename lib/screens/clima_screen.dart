import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/clima.dart';
import '../services/clima_service.dart';
import '../services/location_service.dart';

/// Clima del AMBIENTE en el lugar del productor (Open-Meteo), con el último dato
/// guardado cuando no hay señal y la opción de escribir temperatura y humedad a mano.
///
/// Es el aire del lugar: NO es la temperatura de la masa de cacao ni la del grano.
/// No da veredictos del tipo "clima adecuado": no hay una fuente verificada para
/// esos umbrales.
class ClimaScreen extends StatefulWidget {
  /// Se pueden cambiar en pruebas.
  final ClimaService? clima;
  final LocationService? ubicacion;
  final Future<bool> Function(Uri)? abrirEnlace;
  final DateTime Function()? ahora;

  const ClimaScreen({super.key, this.clima, this.ubicacion, this.abrirEnlace, this.ahora});

  @override
  State<ClimaScreen> createState() => _ClimaScreenState();
}

class _ClimaScreenState extends State<ClimaScreen> {
  late final ClimaService _clima = widget.clima ?? ClimaService();
  late final LocationService _ubicacion = widget.ubicacion ?? LocationService();
  DateTime _ahora() => (widget.ahora ?? DateTime.now)();

  final _tempCtrl = TextEditingController();
  final _humCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _cargando = true;
  ResultadoClima? _resultado;
  String? _problema; // por qué no hay dato nuevo (GPS, internet...)
  UbicacionObtenida? _lugar;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tempCtrl.dispose();
    _humCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _problema = null;
    });

    UbicacionObtenida? lugar;
    String? problema;
    try {
      lugar = await _ubicacion.obtener();
    } on UbicacionException catch (e) {
      problema = e.mensaje;
    } catch (_) {
      problema = 'No se pudo obtener la ubicación.';
    }

    ResultadoClima? resultado;
    if (lugar != null) {
      try {
        resultado = await _clima.consultar(lugar.latitud, lugar.longitud);
      } on ClimaException catch (e) {
        problema = e.mensaje;
      }
    } else {
      // Sin ubicación no se puede consultar, pero el último dato guardado sirve.
      final guardado = await _clima.ultimo();
      if (guardado != null) {
        resultado = ResultadoClima(guardado, desdeCache: true, aviso: '$problema Se muestra el último dato guardado.');
      }
    }

    if (!mounted) return;
    setState(() {
      _lugar = lugar;
      _resultado = resultado;
      _problema = resultado?.aviso == null ? problema : null;
      _cargando = false;
    });
  }

  Future<void> _guardarManual() async {
    if (!_formKey.currentState!.validate()) return;
    final t = double.parse(_tempCtrl.text.trim().replaceAll(',', '.'));
    final h = double.parse(_humCtrl.text.trim().replaceAll(',', '.'));
    final clima = await _clima.guardarManual(
      temperaturaC: t,
      humedadPct: h,
      lat: _lugar?.latitud,
      lng: _lugar?.longitud,
    );
    if (!mounted) return;
    _tempCtrl.clear();
    _humCtrl.clear();
    setState(() {
      _resultado = ResultadoClima(clima);
      _problema = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Guardado. Quedó anotado como dato escrito por usted.')));
  }

  String? _validar(String? v, String nombre, double min, double max) {
    if (v == null || v.trim().isEmpty) return 'Escriba $nombre';
    final n = double.tryParse(v.trim().replaceAll(',', '.'));
    if (n == null) return 'Escriba solo números';
    if (n < min || n > max) return 'Debe estar entre ${min.round()} y ${max.round()}';
    return null;
  }

  String _num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _abrirAtribucion() async {
    final abrir = widget.abrirEnlace ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication));
    try {
      await abrir(ClimaService.enlaceAtribucion);
    } catch (_) {
      // sin navegador o sin señal: el texto del crédito sigue visible
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clima del lugar')),
      body: _cargando
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Buscando su ubicación y el clima…', textAlign: TextAlign.center),
                ]),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _avisoAmbiente(tema),
                  const SizedBox(height: 12),
                  if (_resultado != null) _tarjetaClima(tema, _resultado!),
                  if (_problema != null) _tarjetaProblema(tema, _problema!),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _cargar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                  const SizedBox(height: 20),
                  _formularioManual(tema),
                ],
              ),
            ),
    );
  }

  /// Siempre visible: evita que se confunda el aire con la masa de cacao.
  Widget _avisoAmbiente(ThemeData tema) => Card(
        color: tema.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: tema.colorScheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Este es el clima del ambiente, del aire del lugar. NO es la temperatura de la '
                  'masa de cacao ni la del grano: esa se mide con el termómetro dentro de la masa.',
                  style: tema.textTheme.bodyLarge?.copyWith(color: tema.colorScheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _tarjetaClima(ThemeData tema, ResultadoClima r) {
    final c = r.clima;
    final hace = c.haceCuanto(_ahora());
    final origen = c.esManual ? 'Anotado por usted $hace' : 'Dato de $hace';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.aviso != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tema.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.cloud_off, color: tema.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.aviso!, style: TextStyle(color: tema.colorScheme.onErrorContainer)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            Semantics(
              label: 'Temperatura del ambiente ${_num(c.temperaturaC)} grados. Humedad del aire ${c.humedadPct} por ciento.',
              excludeSemantics: true,
              child: Row(
                children: [
                  Expanded(child: _cifra(tema, 'Temperatura del aire', '${_num(c.temperaturaC)} °C')),
                  Expanded(child: _cifra(tema, 'Humedad del aire', '${c.humedadPct} %')),
                ],
              ),
            ),
            if (!c.esManual) ...[
              const SizedBox(height: 8),
              Text(c.descripcion, style: tema.textTheme.titleMedium),
            ],
            const SizedBox(height: 8),
            Text(origen, key: const Key('antiguedad'), style: tema.textTheme.titleMedium),
            if (!c.esManual) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: _abrirAtribucion,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    ClimaService.atribucion,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      color: tema.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
            if (_lugar != null && _lugar!.esUltimaConocida)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'La ubicación es la última que tenía el teléfono: puede no ser de este lugar.',
                  style: tema.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cifra(ThemeData tema, String titulo, String valor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: tema.textTheme.bodyMedium),
          Text(valor, style: tema.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      );

  Widget _tarjetaProblema(ThemeData tema, String problema) => Card(
        color: tema.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.cloud_off, color: tema.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(problema, style: tema.textTheme.bodyLarge?.copyWith(color: tema.colorScheme.onErrorContainer)),
            ),
          ]),
        ),
      );

  Widget _formularioManual(ThemeData tema) => Form(
        key: _formKey,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Escribirlo a mano', style: tema.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Si no hay señal, anote lo que marca su termómetro y su higrómetro del ambiente. '
                  'Queda guardado en el teléfono.',
                  style: tema.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tempCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Temperatura del aire (°C)', border: OutlineInputBorder()),
                  validator: (v) => _validar(v, 'la temperatura', -60, 60),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _humCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Humedad del aire (%)', border: OutlineInputBorder()),
                  validator: (v) => _validar(v, 'la humedad', 0, 100),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _guardarManual,
                  icon: const Icon(Icons.edit),
                  label: const Text('Guardar lo que anoté'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          ),
        ),
      );
}

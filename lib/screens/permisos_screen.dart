import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:alarmacacao5_0/services/consentimiento_ubicacion.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'home_screen.dart';

class PermisosScreen extends StatefulWidget {
  /// Se pueden cambiar en pruebas.
  final LocationService? ubicacion;

  /// Pantalla a la que se pasa después (por defecto, la principal).
  final WidgetBuilder? siguiente;

  /// Se pueden cambiar en pruebas: leer y guardar la autorización del productor.
  final Future<bool?> Function()? leerConsentimiento;
  final Future<void> Function(bool)? guardarConsentimiento;

  const PermisosScreen({super.key, this.ubicacion, this.siguiente, this.leerConsentimiento, this.guardarConsentimiento});

  @override
  State<PermisosScreen> createState() => _PermisosScreenState();
}

class _PermisosScreenState extends State<PermisosScreen> {
  bool _isLoading = false;
  bool _preguntando = false;
  String? _mensaje;
  bool _errorEsDePermiso = false;

  @override
  void initState() {
    super.initState();
    _empezar();
  }

  /// Ley 1581 de 2012: primero se explica y se pide autorización; el permiso del sistema solo se pide
  /// si el productor aceptó. Si ya había dicho que no, no se le insiste: entra directo (puede cambiarlo en Ajustes).
  Future<void> _empezar() async {
    setState(() => _isLoading = true);
    final acepto = await (widget.leerConsentimiento ?? ConsentimientoUbicacion.obtener)();
    if (!mounted) return;
    if (acepto == null) {
      setState(() {
        _isLoading = false;
        _preguntando = true;
      });
    } else if (acepto) {
      await _probarPermisos();
    } else {
      _continuar();
    }
  }

  Future<void> _responder(bool acepta) async {
    await (widget.guardarConsentimiento ?? ConsentimientoUbicacion.registrar)(acepta);
    if (!mounted) return;
    setState(() => _preguntando = false);
    if (acepta) {
      await _probarPermisos();
    } else {
      _continuar();
    }
  }

  Future<void> _probarPermisos() async {
    setState(() {
      _isLoading = true;
      _mensaje = null;
    });
    try {
      // Solo se pide el permiso: NO se espera una posición GPS, para que la app
      // abra rápido aunque el teléfono esté dentro de una casa o sin señal.
      await (widget.ubicacion ?? LocationService()).asegurarPermiso();
      if (!mounted) return;
      setState(() {
        _mensaje = 'Permiso de ubicación listo.';
        _errorEsDePermiso = false;
      });
      Future.delayed(const Duration(seconds: 1), _continuar);
    } on UbicacionException catch (e) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'Error: ${e.mensaje}\nLa app sirve igual (alarmas y registros). Sin ubicación no podrá '
            'marcar el punto de secado ni ver el clima de su lugar.';
        _errorEsDePermiso = e.abrirAjustes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensaje = 'Error: no se pudo revisar el permiso de ubicación.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _continuar() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.siguiente ?? (_) => const HomeScreen(title: 'Cacao Light 4.0')),
    );
  }

  Widget _pregunta() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ConsentimientoUbicacion.titulo, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(ConsentimientoUbicacion.texto, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(onPressed: () => _responder(true), child: const Text('Sí, usar mi ubicación')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _responder(false), child: const Text('No, ahora no')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_preguntando) {
      return Scaffold(appBar: AppBar(title: const Text('Su ubicación')), body: _pregunta());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Permisos de Ubicación')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_mensaje != null)
                      Text(
                        _mensaje!,
                        style: TextStyle(
                          color: _mensaje!.startsWith('Error') ? Colors.red : Colors.green,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 20),
                    if (_errorEsDePermiso)
                      ElevatedButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('Abrir ajustes'),
                      ),
                    ElevatedButton(
                      onPressed: _probarPermisos,
                      child: const Text('Reintentar Solicitar Permisos'),
                    ),
                    const SizedBox(height: 12),
                    // Sin GPS la app debe seguir funcionando (alarmas y registros).
                    TextButton(
                      onPressed: _continuar,
                      child: const Text('Continuar sin ubicación'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

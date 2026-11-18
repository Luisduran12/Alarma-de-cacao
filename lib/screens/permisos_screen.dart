import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'home_screen.dart';

class PermisosScreen extends StatefulWidget {
  const PermisosScreen({super.key});

  @override
  State<PermisosScreen> createState() => _PermisosScreenState();
}

class _PermisosScreenState extends State<PermisosScreen> {
  bool _isLoading = false;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _probarPermisos();
  }

  Future<void> _probarPermisos() async {
    setState(() {
      _isLoading = true;
      _mensaje = null;
    });
    try {
      final posicion = await LocationService().obtenerUbicacionActual(context);
      if (!mounted) return;
      setState(() {
        _mensaje = 'Ubicación obtenida: Lat ${posicion.latitude}, Lon ${posicion.longitude}';
      });
      // Navegar a HomeScreen tras éxito
      Future.delayed(const Duration(seconds: 2), _continuar);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'Error al obtener ubicación: $e';
      });
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
      MaterialPageRoute(builder: (_) => const HomeScreen(title: 'Cacao Light 4.0')),
    );
  }

  @override
  Widget build(BuildContext context) {
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

import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'home_screen.dart';

class PermisosScreen extends StatefulWidget {
  const PermisosScreen({Key? key}) : super(key: key);

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
      setState(() {
        _mensaje = 'Ubicación obtenida: Lat ${posicion.latitude}, Lon ${posicion.longitude}';
      });
      // Navegar a HomeScreen tras éxito
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen(title: 'Alarma Cacao')),
        );
      });
    } catch (e) {
      setState(() {
        _mensaje = 'Error al obtener ubicación: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
                  ],
                ),
              ),
      ),
    );
  }
}

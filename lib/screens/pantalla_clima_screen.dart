import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';

class PantallaClimaScreen extends StatefulWidget {
  const PantallaClimaScreen({super.key});

  @override
  State<PantallaClimaScreen> createState() => _PantallaClimaScreenState();
}

class _PantallaClimaScreenState extends State<PantallaClimaScreen> {
  Map<String, dynamic>? clima;
  bool cargando = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _cargarClima();
  }

  Future<void> _cargarClima() async {
    try {
      final data = await ClimaService().obtenerClimaDesdeUbicacion();
      setState(() {
        clima = data;
        cargando = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clima para el Cacao')),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: $error'))
              : clima == null
                  ? const Center(child: Text('No se pudo obtener el clima.'))
                  : _buildContenido(),
    );
  }

  Widget _buildContenido() {
    final ciudad = clima!['ciudad'] ?? 'Desconocida';
    final temperatura = clima!['temp'] != null ? '${clima!['temp']} °C' : 'N/D';
    final descripcion = clima!['descripcion'] ?? 'N/D';
    final icono = clima!['icono'];

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icono != null)
            Image.network('https://openweathermap.org/img/wn/$icono@2x.png', width: 100),
          const SizedBox(height: 20),
          Text('📍 Ubicación: $ciudad', style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 10),
          Text('🌡️ Temperatura: $temperatura', style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 10),
          Text('🌥️ Clima: $descripcion', style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _cargarClima,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          )
        ],
      ),
    );
  }
}
  
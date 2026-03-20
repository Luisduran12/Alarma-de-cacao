import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';

class ClimaScreen extends StatefulWidget {
  const ClimaScreen({super.key});

  @override
  State<ClimaScreen> createState() => _ClimaScreenState();
}

class _ClimaScreenState extends State<ClimaScreen> {
  final ClimaService _climaService = ClimaService();
  Map<String, dynamic>? _climaData;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarClima();
  }

  Future<void> _cargarClima() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final datos = await _climaService.obtenerClimaDesdeUbicacion();
      setState(() {
        _climaData = datos;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clima para el Cacao'),
        centerTitle: true,
        backgroundColor: Colors.brown.shade400,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/fondo_clima.jpg',
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.5),
            colorBlendMode: BlendMode.darken,
          ),
          _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _climaData == null
                      ? const Center(
                          child: Text(
                            'No se pudo obtener el clima.',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        )
                      : _buildClimaContent(),
        ],
      ),
    );
  }

  Widget _buildClimaContent() {
    final clima = _climaData!;
    final double temperatura = clima['temp'];
    final int humedad = clima['humedad'];
    final String descripcion = clima['descripcion'];
    final String ciudad = clima['ciudad'];
    final bool climaAdecuado = temperatura > 30;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoTexto('📍 Ciudad: $ciudad'),
          const SizedBox(height: 16),
          _infoTexto('📌 Proceso: secado del cacao'),
          _infoTexto('🌡️ Temp: ${temperatura.toStringAsFixed(1)}°C'),
          _infoTexto('💧 Humedad: $humedad%'),
          _infoTexto('☁️ Clima: $descripcion'),
          const SizedBox(height: 25),
          climaAdecuado
              ? const Text(
                  '✅ El clima es adecuado para el secado del cacao.',
                  style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold),
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠️ El clima NO es adecuado para el secado del cacao.',
                      style: TextStyle(fontSize: 20, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '❌ La temperatura no es suficiente (se recomienda >30 °C).',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
          const SizedBox(height: 30),
          const Divider(thickness: 1, color: Colors.white70),
          const SizedBox(height: 20),
          const Text(
            '📊 Datos actuales:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text('🌡️ Temperatura: ${temperatura.toStringAsFixed(1)} °C',
              style: const TextStyle(fontSize: 18, color: Colors.white)),
          Text('💧 Humedad: $humedad%',
              style: const TextStyle(fontSize: 18, color: Colors.white)),
          Text('☁️ Clima: $descripcion',
              style: const TextStyle(fontSize: 18, color: Colors.white)),
          const SizedBox(height: 30),
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.brown.shade600),
              onPressed: _cargarClima,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTexto(String texto) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 20,
        color: Colors.white,
        shadows: [
          Shadow(
            blurRadius: 3,
            color: Colors.black87,
            offset: Offset(1, 1),
          )
        ],
      ),
    );
  }
}
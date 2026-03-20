import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';
import 'package:alarmacacao5_0/services/evaluador_cacao.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class ClimaCacaoPage extends StatefulWidget {
  const ClimaCacaoPage({super.key});

  @override
  State<ClimaCacaoPage> createState() => _ClimaCacaoPageState();
}

class _ClimaCacaoPageState extends State<ClimaCacaoPage> {
  String mensaje = "⏳ Cargando datos del clima...";
  String procesoSeleccionado = "secado";
  String? iconoClima;
  double? temperatura;
  int? humedad;
  String? descripcion;
  LocationPermission? permisoUbicacion;

  String traducirClima(String condicion) {
    switch (condicion.toLowerCase()) {
      case 'clouds':
        iconoClima = '☁️';
        return 'Nublado';
      case 'clear':
        iconoClima = '☀️';
        return 'Despejado';
      case 'rain':
        iconoClima = '🌧️';
        return 'Lluvia';
      case 'thunderstorm':
        iconoClima = '⛈️';
        return 'Tormenta';
      case 'drizzle':
        iconoClima = '🌦️';
        return 'Llovizna';
      case 'snow':
        iconoClima = '❄️';
        return 'Nieve';
      case 'mist':
      case 'fog':
        iconoClima = '🌫️';
        return 'Niebla';
      default:
        iconoClima = '🌍';
        return condicion[0].toUpperCase() + condicion.substring(1).toLowerCase();
    }
  }

  Future<void> cargarClima() async {
    setState(() {
      mensaje = "⏳ Cargando datos del clima...";
      temperatura = null;
      humedad = null;
      descripcion = null;
    });

    try {
      final clima = await ClimaService().obtenerClimaDesdeUbicacion();

      final double temp = clima['main']['temp'];
      final int hum = clima['main']['humidity'];
      final String condicionOriginal = clima['weather'][0]['main'];
      final String descripcionTraducida = traducirClima(condicionOriginal);

      final String evaluacion = evaluarCondicionesCacao(
        temperatura: temp,
        humedad: hum,
        condicionClima: descripcionTraducida,
        proceso: procesoSeleccionado,
      );

      setState(() {
        temperatura = temp;
        humedad = hum;
        descripcion = descripcionTraducida;
        mensaje = evaluacion;
      });
    } catch (e) {
      setState(() {
        mensaje = "❌ Error al obtener el clima:\n${e.toString()}";
      });
    }
  }

  Future<void> verificarPermisoUbicacion() async {
    permisoUbicacion = await Geolocator.checkPermission();
    if (permisoUbicacion == LocationPermission.denied) {
      permisoUbicacion = await Geolocator.requestPermission();
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    verificarPermisoUbicacion().then((_) {
      if (permisoUbicacion == LocationPermission.always ||
          permisoUbicacion == LocationPermission.whileInUse) {
        _solicitarPermisoYcargarClima();
      } else {
        setState(() {
          mensaje = "❌ Permiso de ubicación no concedido. Por favor, habilítalo en ajustes.";
        });
      }
    });
  }

  Future<void> _solicitarPermisoYcargarClima() async {
    try {
      await LocationService().obtenerUbicacionActual(context);
      await cargarClima();
    } catch (e) {
      setState(() {
        mensaje = "❌ Permiso de ubicación denegado o error: $e";
        temperatura = null;
        humedad = null;
        descripcion = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Clima para el Cacao"),
        centerTitle: true,
        backgroundColor: Colors.brown.shade700,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: cargarClima,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: procesoSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Selecciona el proceso',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'secado', child: Text('Secado')),
                  DropdownMenuItem(value: 'fermentación', child: Text('Fermentación')),
                ],
                onChanged: (value) {
                  setState(() {
                    procesoSeleccionado = value!;
                  });
                  cargarClima();
                },
              ),
              const SizedBox(height: 30),
              if (temperatura != null && humedad != null && descripcion != null)
                Column(
                  children: [
                    Text(
                      iconoClima ?? '',
                      style: const TextStyle(fontSize: 64),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '🌡️ Temperatura: ${temperatura!.toStringAsFixed(1)}°C',
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      '💧 Humedad: $humedad%',
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      '☁️ Clima: $descripcion',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const Divider(height: 30),
                  ],
                ),
              Text(
                mensaje,
                textAlign: TextAlign.left,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: cargarClima,
                icon: const Icon(Icons.refresh),
                label: const Text("Actualizar clima"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  /// Obtiene la ubicación GPS actual del dispositivo
  Future<Position> obtenerUbicacionActual(BuildContext context) async {
    // Verifica si los servicios de ubicación están activados
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      throw Exception('❌ Los servicios de ubicación están desactivados.');
    }

    // Verifica el estado del permiso de ubicación
    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        throw Exception('❌ Permiso de ubicación denegado.');
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      // Mostrar diálogo para guiar al usuario a ajustes
      await _mostrarDialogoPermisoDenegado(context);
      throw Exception('❌ Permiso de ubicación denegado permanentemente. Habilítalo en los ajustes.');
    }

    // Devuelve la posición con alta precisión
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _mostrarDialogoPermisoDenegado(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // El usuario debe pulsar un botón
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permiso de ubicación denegado'),
          content: const Text(
              'El permiso de ubicación ha sido denegado permanentemente. Por favor, habilítalo manualmente en los ajustes de la aplicación para que funcione correctamente.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Abrir Ajustes'),
              onPressed: () {
                openAppSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

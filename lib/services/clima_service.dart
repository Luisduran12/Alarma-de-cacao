import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Servicio para consultar el clima usando OpenWeatherMap y la ubicación del dispositivo.
///
/// La clave NO está en el código. Se inyecta al compilar desde el archivo `.env`
/// (que está en .gitignore):
///
///   flutter run --dart-define-from-file=.env
///   flutter build apk --release --dart-define-from-file=.env
///
/// Ver `.env.example`.
class ClimaService {
  static const String _apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');

  /// Indica si la app se compiló con una clave de OpenWeatherMap.
  static bool get tieneClave => _apiKey.isNotEmpty;

  void _verificarClave() {
    if (!tieneClave) {
      throw Exception(
        'Falta la clave de OpenWeatherMap. Compila con --dart-define-from-file=.env '
        '(ver .env.example).',
      );
    }
  }

  /// Consulta el clima actual según el nombre de la ciudad (ej: 'Cúcuta,CO').
  Future<Map<String, dynamic>> obtenerClimaPorCiudad(String ciudad) async {
    _verificarClave();
    final uri = Uri.https('api.openweathermap.org', '/data/2.5/weather', {
      'q': ciudad,
      'appid': _apiKey,
      'units': 'metric',
      'lang': 'es',
    });

    try {
      final respuesta = await http.get(uri).timeout(const Duration(seconds: 15));
      if (respuesta.statusCode == 200) {
        return json.decode(respuesta.body) as Map<String, dynamic>;
      }
      throw Exception('Error ${respuesta.statusCode}: no se pudo obtener el clima para $ciudad');
    } catch (e) {
      throw Exception('Error de red al consultar clima por ciudad: $e');
    }
  }

  /// Consulta el clima actual usando GPS y retorna datos organizados.
  ///
  /// Devuelve: 'temp', 'humedad', 'condicion', 'descripcion', 'icono', 'ciudad'.
  Future<Map<String, dynamic>> obtenerClimaDesdeUbicacion() async {
    _verificarClave();
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        throw Exception('Permiso de ubicación denegado.');
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        throw Exception('El GPS está desactivado. Actívalo e intenta de nuevo.');
      }

      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) {
          throw Exception('Permiso de ubicación denegado.');
        }
      }
      if (permiso == LocationPermission.deniedForever) {
        await openAppSettings();
        throw Exception('Permiso denegado permanentemente. Habilítalo en Ajustes.');
      }

      final Position posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final uri = Uri.https('api.openweathermap.org', '/data/2.5/weather', {
        'lat': '${posicion.latitude}',
        'lon': '${posicion.longitude}',
        'appid': _apiKey,
        'units': 'metric',
        'lang': 'es',
      });

      final respuesta = await http.get(uri).timeout(const Duration(seconds: 15));
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body);
        return {
          'temp': datos['main']['temp'],
          'humedad': datos['main']['humidity'],
          'condicion': datos['weather'][0]['main'],
          'descripcion': datos['weather'][0]['description'],
          'icono': datos['weather'][0]['icon'],
          'ciudad': datos['name'],
        };
      }
      throw Exception('Error ${respuesta.statusCode}: no se pudo obtener el clima.');
    } catch (e) {
      throw Exception('Error al obtener clima por ubicación: $e');
    }
  }
}

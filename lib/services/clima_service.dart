  import 'dart:convert';
  import 'package:http/http.dart' as http;
  import 'package:geolocator/geolocator.dart';
  import 'package:permission_handler/permission_handler.dart';

  /// Servicio para consultar el clima usando OpenWeatherMap y la ubicación del dispositivo
  class ClimaService {
    static const String _apiKey = 'ff1552a525c006cab8b85bf26c45d0f7';

    /// 🌍 Consulta el clima actual según el nombre de la ciudad (ej: 'Cúcuta,CO')
    Future<Map<String, dynamic>> obtenerClimaPorCiudad(String ciudad) async {
      final url =
          'https://api.openweathermap.org/data/2.5/weather?q=$ciudad&appid=$_apiKey&units=metric&lang=es';

      try {
        final respuesta = await http.get(Uri.parse(url));
        if (respuesta.statusCode == 200) {
          return json.decode(respuesta.body);
        } else {
          throw Exception('❌ Error ${respuesta.statusCode}: No se pudo obtener el clima para $ciudad');
        }
      } catch (e) {
        throw Exception('⚠️ Error de red al consultar clima por ciudad: $e');
      }
    }

    /// 📍 Consulta el clima actual usando GPS y retorna datos organizados
    ///
    /// Devuelve:
    /// - 'temp': Temperatura en °C
    /// - 'humedad': Porcentaje de humedad
    /// - 'condicion': Ej. 'Clouds'
    /// - 'descripcion': Ej. 'nubes dispersas'
    /// - 'icono': Código de ícono (ej. 01d)
    /// - 'ciudad': Nombre de la ciudad detectada
    Future<Map<String, dynamic>> obtenerClimaDesdeUbicacion() async {
      try {
        // ✅ Solicita permisos con permission_handler
        final status = await Permission.location.request();
        if (!status.isGranted) {
          throw Exception('❌ Permiso de ubicación denegado.');
        }

        // 1. Verifica si la ubicación está activada
        if (!await Geolocator.isLocationServiceEnabled()) {
          await Geolocator.openLocationSettings();
          throw Exception('📴 El GPS está desactivado. Se abrió configuración, actívalo manualmente.');
        }

        // 2. Verifica y solicita permisos desde Geolocator también
        LocationPermission permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
          if (permiso == LocationPermission.denied) {
            throw Exception('❌ Permiso de ubicación denegado.');
          }
        }
        if (permiso == LocationPermission.deniedForever) {
          await openAppSettings();
          throw Exception('⛔ Permiso denegado permanentemente. Se abrió configuración para habilitarlo.');
        }

        // 3. Obtiene coordenadas GPS actuales
        final Position posicion = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        final url =
            'https://api.openweathermap.org/data/2.5/weather?lat=${posicion.latitude}&lon=${posicion.longitude}&appid=$_apiKey&units=metric&lang=es';

        final respuesta = await http.get(Uri.parse(url));
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
        } else {
          throw Exception('❌ Error ${respuesta.statusCode}: No se pudo obtener el clima.');
        }
      } catch (e) {
        throw Exception('⚠️ Error al obtener clima por ubicación: $e');
      }
    }
  }

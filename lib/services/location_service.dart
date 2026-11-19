import 'package:geolocator/geolocator.dart';

import 'consentimiento_ubicacion.dart';

/// Una ubicación GPS ya obtenida. No necesita internet: el GPS del teléfono
/// funciona sin señal de datos.
class UbicacionObtenida {
  final double latitud;
  final double longitud;

  /// Error estimado en metros (null si el teléfono no lo informa).
  final double? precisionMetros;

  /// true si el GPS no logró una posición nueva a tiempo y se usó la última que
  /// el teléfono tenía guardada. Puede ser de otro lugar: hay que decírselo al usuario.
  final bool esUltimaConocida;

  /// Cuándo se tomó la posición (null si el teléfono no lo informa).
  final DateTime? momento;

  const UbicacionObtenida({
    required this.latitud,
    required this.longitud,
    this.precisionMetros,
    this.esUltimaConocida = false,
    this.momento,
  });

  /// "hace 5 min", "hace 2 h", "hace 3 días"; null si no se sabe.
  String? hace(DateTime ahora) {
    final m = momento;
    if (m == null) return null;
    final d = ahora.difference(m);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
  }
}

/// El GPS no se pudo usar. [mensaje] va escrito para el productor.
class UbicacionException implements Exception {
  final String mensaje;

  /// true si la solución es que el usuario cambie un permiso en los ajustes.
  final bool abrirAjustes;

  /// true si falta la autorización del productor dentro de la app (Ley 1581), no el permiso de Android.
  final bool faltaConsentimiento;
  const UbicacionException(this.mensaje, {this.abrirAjustes = false, this.faltaConsentimiento = false});

  @override
  String toString() => mensaje;
}

/// Lo que se necesita del sistema. Se puede cambiar en pruebas.
abstract class PlataformaUbicacion {
  Future<bool> servicioActivado();
  Future<LocationPermission> permiso();
  Future<LocationPermission> pedirPermiso();
  Future<Position> posicionActual(Duration limite);
  Future<Position?> ultimaConocida();
}

class _PlataformaGeolocator implements PlataformaUbicacion {
  const _PlataformaGeolocator();

  @override
  Future<bool> servicioActivado() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> permiso() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> pedirPermiso() => Geolocator.requestPermission();

  @override
  Future<Position> posicionActual(Duration limite) => Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: limite,
      );

  @override
  Future<Position?> ultimaConocida() => Geolocator.getLastKnownPosition();
}

/// Obtiene la ubicación por GPS, sin internet y sin pantallas: quien lo llama
/// decide cómo mostrar los errores.
class LocationService {
  /// Cuánto se espera al GPS antes de usar la última posición conocida. Un GPS
  /// frío puede tardar; dentro de una casa o un cajón a veces no responde.
  /// (Valor de la app, no de una norma.)
  static const esperaPorDefecto = Duration(seconds: 30);

  final PlataformaUbicacion _plataforma;
  final Duration espera;

  /// Si el productor autorizó usar la ubicación (true), la rechazó (false) o aún no se le pregunta (null).
  final Future<bool?> Function() _consentimiento;

  LocationService({
    PlataformaUbicacion? plataforma,
    this.espera = esperaPorDefecto,
    Future<bool?> Function()? consentimiento,
  })  : _plataforma = plataforma ?? const _PlataformaGeolocator(),
        _consentimiento = consentimiento ?? ConsentimientoUbicacion.obtener;

  /// Comprueba que el GPS esté encendido y que haya permiso; lo pide si hace falta.
  /// Lanza [UbicacionException] si no se puede. NO espera ninguna posición, así que
  /// es rápido y sirve para la pantalla de permisos del arranque.
  Future<void> asegurarPermiso() async {
    // Primero la autorización del productor: sin ella ni siquiera se le pide el permiso al sistema.
    if (await _consentimiento() != true) {
      throw const UbicacionException(
        'Falta su autorización para usar la ubicación. Puede darla en Ajustes > Privacidad.',
        faltaConsentimiento: true,
      );
    }
    if (!await _plataforma.servicioActivado()) {
      throw const UbicacionException('El GPS está apagado. Enciéndalo en los ajustes del teléfono.');
    }

    var permiso = await _plataforma.permiso();
    if (permiso == LocationPermission.denied) {
      permiso = await _plataforma.pedirPermiso();
    }
    if (permiso == LocationPermission.denied) {
      throw const UbicacionException('No se dio permiso de ubicación.');
    }
    if (permiso == LocationPermission.deniedForever) {
      throw const UbicacionException(
        'El permiso de ubicación está bloqueado. Actívelo en los ajustes de la aplicación.',
        abrirAjustes: true,
      );
    }
  }

  /// Obtiene la posición actual. Si el GPS no responde a tiempo, usa la última
  /// que tenía el teléfono (y lo marca en [UbicacionObtenida.esUltimaConocida]).
  Future<UbicacionObtenida> obtener() async {
    await asegurarPermiso();

    try {
      final p = await _plataforma.posicionActual(espera);
      return _convertir(p, esUltima: false);
    } catch (_) {
      // Tiempo agotado u otro fallo del GPS: se intenta con la última posición guardada.
    }

    Position? ultima;
    try {
      ultima = await _plataforma.ultimaConocida();
    } catch (_) {
      ultima = null;
    }
    if (ultima != null) return _convertir(ultima, esUltima: true);
    throw const UbicacionException(
      'No se pudo encontrar la ubicación. Salga a un lugar abierto y vuelva a intentar.',
    );
  }

  static UbicacionObtenida _convertir(Position p, {required bool esUltima}) => UbicacionObtenida(
        latitud: p.latitude,
        longitud: p.longitude,
        precisionMetros: p.accuracy > 0 ? p.accuracy : null,
        esUltimaConocida: esUltima,
        momento: p.timestamp,
      );
}

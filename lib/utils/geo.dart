import 'dart:math' as math;

/// Distancia en kilómetros sobre la superficie de la Tierra entre dos puntos
/// (fórmula del haversine; radio medio de la Tierra 6371 km).
double distanciaKm(double lat1, double lng1, double lat2, double lng2) {
  const radioKm = 6371.0;
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * radioKm * math.asin(math.min(1, math.sqrt(a)));
}

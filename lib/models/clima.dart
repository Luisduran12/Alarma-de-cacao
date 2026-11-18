import '../data/codigos_clima.dart';

enum FuenteClima { openMeteo, manual }

/// El clima del AMBIENTE (el aire del lugar). No es la temperatura de la masa
/// de cacao ni la del grano.
class Clima {
  final double temperaturaC;
  final int humedadPct;
  final int? codigoWmo;
  final bool? esDeDia;

  /// Momento (en UTC) en que el dato fue válido: la hora de la medición del
  /// modelo (Open-Meteo) o el momento en que el usuario lo anotó (manual).
  final DateTime medidoEn;
  final FuenteClima fuente;

  /// Lugar al que corresponde el dato (redondeado), si se conoce.
  final double? latitud;
  final double? longitud;

  const Clima({
    required this.temperaturaC,
    required this.humedadPct,
    this.codigoWmo,
    this.esDeDia,
    required this.medidoEn,
    required this.fuente,
    this.latitud,
    this.longitud,
  });

  bool get esManual => fuente == FuenteClima.manual;

  String get descripcion => CodigosClima.descripcion(codigoWmo);

  /// "hace un momento", "hace 25 min", "hace 1 hora", "hace 5 horas", "hace 2 días".
  String haceCuanto(DateTime ahora) {
    final d = ahora.toUtc().difference(medidoEn.toUtc());
    if (d.isNegative || d.inMinutes < 1) return 'hace un momento';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} ${d.inHours == 1 ? 'hora' : 'horas'}';
    return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
  }

  Map<String, dynamic> toJson() => {
        'temperaturaC': temperaturaC,
        'humedadPct': humedadPct,
        'codigoWmo': codigoWmo,
        'esDeDia': esDeDia,
        'medidoEn': medidoEn.toUtc().toIso8601String(),
        'fuente': fuente.name,
        'latitud': latitud,
        'longitud': longitud,
      };

  static Clima? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['temperaturaC'], h = j['humedadPct'];
    final medido = DateTime.tryParse((j['medidoEn'] as String?) ?? '');
    if (t is! num || h is! num || medido == null) return null;
    return Clima(
      temperaturaC: t.toDouble(),
      humedadPct: h.round(),
      codigoWmo: (j['codigoWmo'] as num?)?.toInt(),
      esDeDia: j['esDeDia'] as bool?,
      medidoEn: medido.toUtc(),
      fuente: FuenteClima.values.where((f) => f.name == j['fuente']).firstOrNull ?? FuenteClima.openMeteo,
      latitud: (j['latitud'] as num?)?.toDouble(),
      longitud: (j['longitud'] as num?)?.toDouble(),
    );
  }
}

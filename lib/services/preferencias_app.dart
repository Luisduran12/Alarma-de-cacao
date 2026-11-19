import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TamanoLetra {
  normal('normal', 'Normal', 1.0),
  grande('grande', 'Grande', 1.3),
  muyGrande('muy_grande', 'Muy grande', 1.6);

  final String codigo;
  final String nombre;

  /// Se multiplica por el tamaño de letra que ya tenga el teléfono en sus ajustes.
  final double factor;
  const TamanoLetra(this.codigo, this.nombre, this.factor);

  static TamanoLetra desdeCodigo(String? c) => values.firstWhere((t) => t.codigo == c, orElse: () => normal);
}

/// Ajustes de la app que se guardan en el teléfono: letra, contraste y ahorro de batería.
/// Los demás ajustes (permisos, copia de seguridad...) viven en sus propios servicios.
class PreferenciasApp extends ChangeNotifier {
  static const _kTamano = 'pref_tamano_letra';
  static const _kContraste = 'pref_alto_contraste';
  static const _kBateria = 'pref_ahorro_bateria';

  TamanoLetra _tamano;
  bool _altoContraste;
  bool _ahorroBateria;

  PreferenciasApp({TamanoLetra tamano = TamanoLetra.normal, bool altoContraste = false, bool ahorroBateria = false})
      : _tamano = tamano,
        _altoContraste = altoContraste,
        _ahorroBateria = ahorroBateria;

  TamanoLetra get tamano => _tamano;
  bool get altoContraste => _altoContraste;

  /// Con el ahorro de batería la app NO hace trabajo por su cuenta al abrir (no reintenta fotos ni
  /// nombres de lugar): todo se hace cuando el productor lo pide.
  bool get ahorroBateria => _ahorroBateria;

  /// La instancia de la app (se carga una vez al arrancar). En pruebas se puede reemplazar.
  static PreferenciasApp instancia = PreferenciasApp();

  static Future<PreferenciasApp> cargar() async {
    final p = await SharedPreferences.getInstance();
    return instancia = PreferenciasApp(
      tamano: TamanoLetra.desdeCodigo(p.getString(_kTamano)),
      altoContraste: p.getBool(_kContraste) ?? false,
      ahorroBateria: p.getBool(_kBateria) ?? false,
    );
  }

  /// Lee solo el ahorro de batería (para el arranque, antes de que exista la pantalla).
  static Future<bool> ahorroDeBateriaActivo() async => (await SharedPreferences.getInstance()).getBool(_kBateria) ?? false;

  Future<void> cambiarTamano(TamanoLetra t) async {
    _tamano = t;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_kTamano, t.codigo);
  }

  Future<void> cambiarAltoContraste(bool v) async {
    _altoContraste = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_kContraste, v);
  }

  Future<void> cambiarAhorroBateria(bool v) async {
    _ahorroBateria = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_kBateria, v);
  }

  /// Vuelve a los valores de fábrica (se usa al borrar todos los datos).
  Future<void> restablecer() async {
    _tamano = TamanoLetra.normal;
    _altoContraste = false;
    _ahorroBateria = false;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTamano);
    await p.remove(_kContraste);
    await p.remove(_kBateria);
  }
}

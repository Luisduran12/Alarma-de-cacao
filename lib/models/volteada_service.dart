import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/volteada.dart';

class VolteadaService {
  static const String _key = 'volteadas';

  /// Guarda una nueva volteada en SharedPreferences
  Future<void> guardarVolteada(Volteada volteada) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existentes = prefs.getStringList(_key) ?? [];

    final String jsonVolteada = jsonEncode(volteada.toJson());
    existentes.add(jsonVolteada);

    await prefs.setStringList(_key, existentes);
  }

  /// Carga todas las volteadas guardadas
  Future<List<Volteada>> cargarVolteadas() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> data = prefs.getStringList(_key) ?? [];

    final List<Volteada> resultado = [];

    for (final item in data) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(item);
        final volteada = Volteada.fromJson(jsonMap);
        resultado.add(volteada);
      } catch (e) {
        // Si falla una entrada, la ignoramos pero continuamos
        continue;
      }
    }

    return resultado;
  }

  /// Obtiene todas las volteadas de un lote específico
  Future<List<Volteada>> obtenerVolteadasPorLote(String loteId) async {
    final todas = await cargarVolteadas();
    return todas.where((v) => v.loteId == loteId).toList();
  }

  /// Obtiene solo las volteadas confirmadas de un lote
  Future<List<Volteada>> obtenerConfirmadasDelLote(String loteId) async {
    final todas = await obtenerVolteadasPorLote(loteId);
    return todas.where((v) => v.confirmada).toList();
  }

  /// Borra todas las volteadas de la memoria local
  Future<void> borrarTodo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Guarda múltiples volteadas (por ejemplo, al crear un lote)
  Future<void> guardarVariasVolteadas(List<Volteada> nuevas) async {
    final prefs = await SharedPreferences.getInstance();
    final existentes = prefs.getStringList(_key) ?? [];

    final nuevasCodificadas = nuevas.map((v) => jsonEncode(v.toJson())).toList();
    final todas = [...existentes, ...nuevasCodificadas];

    await prefs.setStringList(_key, todas);
  }
}

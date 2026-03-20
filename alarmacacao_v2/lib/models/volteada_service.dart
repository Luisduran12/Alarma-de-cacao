// lib/services/volteada_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/volteada.dart';

class VolteadaService {
  static const String _key = 'volteadas';

  /// Guarda una nueva volteada agregándola a la lista existente
  Future<void> guardarVolteada(Volteada volteada) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> existentes = prefs.getStringList(_key) ?? [];

    final String jsonVolteada = jsonEncode(volteada.toJson());
    existentes.add(jsonVolteada);

    await prefs.setStringList(_key, existentes);
  }

  /// Carga todas las volteadas guardadas desde SharedPreferences
  Future<List<Volteada>> cargarVolteadas() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> data = prefs.getStringList(_key) ?? [];

    return data.map((jsonStr) {
      try {
        return Volteada.fromJson(jsonDecode(jsonStr));
      } catch (_) {
        return null; // Si hay error en un JSON, lo descarta
      }
    }).whereType<Volteada>().toList(); // Elimina valores nulos
  }

  /// Devuelve solo las volteadas asociadas a un lote específico
  Future<List<Volteada>> obtenerConfirmadasDelLote(String loteId) async {
    final todas = await cargarVolteadas();
    return todas.where((v) => v.loteId == loteId).toList();
  }

  /// Borra todas las volteadas almacenadas
  Future<void> borrarTodo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

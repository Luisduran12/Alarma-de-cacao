import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/volteada.dart';

class VolteadaService {
  static const _storageKey = 'volteadas';

  /// Carga todas las volteadas almacenadas.
  Future<List<Volteada>> cargarVolteadas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getStringList(_storageKey) ?? [];
      return data.map((v) => Volteada.fromJson(jsonDecode(v))).toList();
    } catch (e) {
      print('❌ Error al cargar volteadas: $e');
      return [];
    }
  }

  /// Guarda toda la lista de volteadas.
  Future<void> guardarVolteadas(List<Volteada> volteadas) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = volteadas.map((v) => jsonEncode(v.toJson())).toList();
      await prefs.setStringList(_storageKey, data);
    } catch (e) {
      print('❌ Error al guardar volteadas: $e');
    }
  }

  /// Guarda una sola volteada (agregándola a la lista existente).
  Future<void> guardarVolteada(Volteada nuevaVolteada) async {
    try {
      final listaActual = await cargarVolteadas();
      listaActual.add(nuevaVolteada);
      await guardarVolteadas(listaActual);
    } catch (e) {
      print('❌ Error al guardar una volteada: $e');
    }
  }

  /// Elimina una volteada por ID.
  Future<void> eliminarVolteadaPorId(String id) async {
    try {
      final lista = await cargarVolteadas();
      final nuevaLista = lista.where((v) => v.id != id).toList();
      await guardarVolteadas(nuevaLista);
    } catch (e) {
      print('❌ Error al eliminar volteada: $e');
    }
  }

  /// Elimina todas las volteadas (limpieza total).
  Future<void> limpiarVolteadas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      print('❌ Error al limpiar volteadas: $e');
    }
  }

  /// 🔍 Obtiene todas las volteadas ya confirmadas para un lote específico.
  Future<List<Volteada>> obtenerConfirmadasDelLote(String loteId) async {
    try {
      final todas = await cargarVolteadas();
      return todas.where((v) => v.loteId == loteId).toList();
    } catch (e) {
      print('❌ Error al filtrar volteadas confirmadas: $e');
      return [];
    }
  }
}

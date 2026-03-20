import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarmacacao5_0/models/lote.dart';

class LoteService {
  static const String _lotesKey = 'lotes_guardados';

  /// Carga todos los lotes guardados.
  Future<List<Lote>> loadLotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? lotesJson = prefs.getString(_lotesKey);
      if (lotesJson == null) return [];
      final List<dynamic> jsonList = json.decode(lotesJson);
      return jsonList.map((json) => Lote.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error al cargar lotes: $e');
      return [];
    }
  }

  /// Guarda todos los lotes en SharedPreferences.
  Future<void> saveLotes(List<Lote> lotes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String lotesJson = json.encode(lotes.map((lote) => lote.toJson()).toList());
      await prefs.setString(_lotesKey, lotesJson);
    } catch (e) {
      print('❌ Error al guardar lotes: $e');
    }
  }

  /// Agrega un nuevo lote.
  Future<void> addLote(Lote lote) async {
    try {
      List<Lote> currentLotes = await loadLotes();
      currentLotes.add(lote);
      await saveLotes(currentLotes);
    } catch (e) {
      print('❌ Error al agregar lote: $e');
    }
  }

  /// Actualiza un lote existente.
  Future<void> updateLote(Lote updatedLote) async {
    try {
      List<Lote> currentLotes = await loadLotes();
      final index = currentLotes.indexWhere((l) => l.id == updatedLote.id);
      if (index != -1) {
        currentLotes[index] = updatedLote;
        await saveLotes(currentLotes);
      }
    } catch (e) {
      print('❌ Error al actualizar lote: $e');
    }
  }

  /// Elimina un lote por su ID.
  Future<void> deleteLote(String loteId) async {
    try {
      List<Lote> currentLotes = await loadLotes();
      currentLotes.removeWhere((l) => l.id == loteId);
      await saveLotes(currentLotes);
    } catch (e) {
      print('❌ Error al eliminar lote: $e');
    }
  }

  /// 🔍 Obtiene un lote específico por su ID.
  Future<Lote?> obtenerLotePorId(String id) async {
    try {
      List<Lote> lotes = await loadLotes();
      final resultado = lotes.where((lote) => lote.id == id);
      return resultado.isNotEmpty ? resultado.first : null;
    } catch (e) {
      print('❌ Error al obtener lote por ID: $e');
      return null;
    }
  }
}

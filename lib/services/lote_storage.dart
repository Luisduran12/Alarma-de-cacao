import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/lote.dart';

class LoteStorageService {
  Future<List<Lote>> cargarLotes() async {
    final prefs = await SharedPreferences.getInstance();
    final lotesJson = prefs.getString('lotes_data');
    if (lotesJson == null) return [];
    final List<dynamic> jsonList = jsonDecode(lotesJson);
    return jsonList.map((json) => Lote.fromJson(json)).toList();
  }

  Future<void> guardarLotes(List<Lote> lotes) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = lotes.map((l) => l.toJson()).toList();
    await prefs.setString('lotes_data', jsonEncode(jsonList));
  }

  Future<void> eliminarLote(String id, List<Lote> lotes) async {
    lotes.removeWhere((lote) => lote.id == id);
    await guardarLotes(lotes);
  }
}

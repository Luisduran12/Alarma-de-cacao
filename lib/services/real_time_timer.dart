import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class RealTimeTimer {
  static const String _startTimeKey = 'timer_start_time';
  static const String _durationKey = 'timer_duration';
  static const String _isActiveKey = 'timer_is_active';
  
  Timer? _timer;
  int? _startTime;
  int? _duration;
  bool _isActive = false;

  String? _title;
  String? _mensaje;
  
  // Callback para actualizar la UI
  Function(int elapsed)? onTimeUpdate;
  Function()? onTimerComplete;

  // Iniciar temporizador con duración y mensaje
  Future<void> startTimer(int durationInSeconds, {String? title, String? mensaje}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    _startTime = now;
    _duration = durationInSeconds;
    _isActive = true;
    _title = title;
    _mensaje = mensaje;

    // Guardar estado en persistencia
    await prefs.setInt(_startTimeKey, _startTime!);
    await prefs.setInt(_durationKey, _duration!);
    await prefs.setBool(_isActiveKey, _isActive);

    if (_title != null && _mensaje != null) {
      print("⏱️ Temporizador iniciado para '${_title!}': ${_mensaje!}");
    }

    _startPeriodicUpdate();
  }

  // Cargar estado desde persistencia
  Future<void> loadTimerState() async {
    final prefs = await SharedPreferences.getInstance();

    _startTime = prefs.getInt(_startTimeKey);
    _duration = prefs.getInt(_durationKey);
    _isActive = prefs.getBool(_isActiveKey) ?? false;

    if (_isActive && _startTime != null && _duration != null) {
      _startPeriodicUpdate();
    }
  }

  // Obtener tiempo transcurrido
  int getElapsedTime() {
    if (!_isActive || _startTime == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now - _startTime!;
  }

  // Obtener tiempo restante
  int getRemainingTime() {
    if (!_isActive || _duration == null) return 0;

    final elapsed = getElapsedTime();
    return (_duration! - elapsed).clamp(0, _duration!);
  }

  // Verificar si el temporizador está activo
  bool isTimerActive() => _isActive;

  // Detener temporizador
  Future<void> stopTimer() async {
    _isActive = false;
    _timer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isActiveKey, false);
  }

  // Reiniciar temporizador
  Future<void> resetTimer() async {
    await stopTimer();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_startTimeKey);
    await prefs.remove(_durationKey);
    await prefs.remove(_isActiveKey);
  }

  // Iniciar actualización periódica
  void _startPeriodicUpdate() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = getRemainingTime();

      if (onTimeUpdate != null) {
        onTimeUpdate!(getElapsedTime());
      }

      if (remaining <= 0) {
        _timer?.cancel();
        _isActive = false;

        if (_title != null && _mensaje != null) {
          print("✅ ¡Temporizador completado para '${_title!}': ${_mensaje!}!");
        }

        if (onTimerComplete != null) {
          onTimerComplete!();
        }
      }
    });
  }

  // Limpiar recursos
  void dispose() {
    _timer?.cancel();
  }
}

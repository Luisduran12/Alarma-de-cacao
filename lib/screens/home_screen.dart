// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/screens/ver_registro_screen.dart';
import 'package:alarmacacao5_0/screens/clima_screen.dart';

class HomeScreen extends StatefulWidget {
  final String title;
  final String? notificationPayload;

  const HomeScreen({super.key, required this.title, this.notificationPayload});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LoteService _loteService = LoteService();
  final Uuid _uuid = const Uuid();
  final TextEditingController _customLoteTitleController = TextEditingController();
  final List<TextEditingController> _customHourControllers = List.generate(5, (_) => TextEditingController());

  List<Lote> _lotesGuardados = [];
  bool _isLoading = false;
  bool _isCountdownActive = false;
  List<int> _alarmCycles = [];
  int _currentCycleIndex = 0;
  int _currentCycleSecondsRemaining = 0;
  int _totalCountdownSeconds = 0;
  late Timer _timer;
  double _progressValue = 0.0;
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _cargarLotesDesdeServicio();
    _inicializarVideo();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isCountdownActive && _currentCycleSecondsRemaining > 0) {
        setState(() {
          _currentCycleSecondsRemaining--;
          _actualizarProgreso();
        });
      }
      if (_isCountdownActive && _currentCycleSecondsRemaining == 0) {
        _avanzarAlSiguienteCiclo();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _videoController.dispose();
    _customLoteTitleController.dispose();
    for (var controller in _customHourControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _inicializarVideo() async {
    _videoController = VideoPlayerController.asset('assets/videos/background_video.mp4');
    await _videoController.initialize();
    _videoController.setLooping(true);
    _videoController.setVolume(0);
    _videoController.play();
    if (mounted) setState(() {});
  }

  Future<void> _cargarLotesDesdeServicio() async {
    _lotesGuardados = await _loteService.loadLotes();
    setState(() {});
  }

  Future<void> _guardarLotesDesdeServicio() async {
    await _loteService.saveLotes(_lotesGuardados);
  }

  void _startCountdown(List<int> cyclesInHours) {
    setState(() {
      _alarmCycles = cyclesInHours.map((h) => h * 3600).toList();
      _totalCountdownSeconds = _alarmCycles.fold(0, (sum, s) => sum + s);
      _currentCycleIndex = 0;
      _currentCycleSecondsRemaining = _alarmCycles.isNotEmpty ? _alarmCycles[0] : 0;
      _isCountdownActive = true;
      _progressValue = 0.0;
    });
  }

  void _actualizarProgreso() {
    if (_totalCountdownSeconds == 0) return;
    int secondsPassed = 0;
    for (int i = 0; i < _currentCycleIndex; i++) {
      secondsPassed += _alarmCycles[i];
    }
    secondsPassed += (_alarmCycles[_currentCycleIndex] - _currentCycleSecondsRemaining);

    setState(() {
      _progressValue = secondsPassed / _totalCountdownSeconds;
    });
  }

  void _avanzarAlSiguienteCiclo() {
    if (_currentCycleIndex < _alarmCycles.length - 1) {
      _currentCycleIndex++;
      _currentCycleSecondsRemaining = _alarmCycles[_currentCycleIndex];
    } else {
      _isCountdownActive = false;
      _progressValue = 1.0;
      _mostrarMensaje('¡Proceso de fermentación completado!');
      _isLoading = false;
    }
  }

  Future<void> _setPredeterminedAlarm() async {
    _startCountdown([48]);

    final nuevoLote = Lote(
      id: _uuid.v4(),
      title: 'Lote Predeterminado ${DateTime.now().hour}:${DateTime.now().minute}',
      volteadas: [],
      status: 'en proceso',
      createdAt: DateTime.now(),
    );

    setState(() {
      _lotesGuardados.add(nuevoLote);
      _isLoading = true;
      _progressValue = 0.0;
    });

    await _guardarLotesDesdeServicio();

    await AlarmScheduler().programarAlarmasPredeterminadas(
      nuevoLote,
      (progress) {
        if (mounted) setState(() => _progressValue = progress);
      },
      (completedLote) async {
        final index = _lotesGuardados.indexWhere((l) => l.id == completedLote.id);
        if (index != -1) {
          setState(() {
            _lotesGuardados[index] = completedLote;
            _isLoading = false;
            _progressValue = 1.0;
            _isCountdownActive = false;
          });
          await _guardarLotesDesdeServicio();
          _mostrarMensaje('Simulación completada y lote guardado.');
        }
      },
    );
  }

  Future<void> _configureCustomAlarm() async {
    final Lote? newLote = await AlarmScheduler().mostrarDialogoConfigurarYProgramar(
      context,
      onProgressUpdate: (progress) {
        if (mounted) setState(() => _progressValue = progress);
      },
      onLoteCompleted: (completedLote) async {
        final index = _lotesGuardados.indexWhere((l) => l.id == completedLote.id);
        if (index != -1) {
          setState(() {
            _lotesGuardados[index] = completedLote;
            _isLoading = false;
            _isCountdownActive = false;
            _progressValue = 1.0;
          });
        } else {
          setState(() {
            _lotesGuardados.add(completedLote);
            _isLoading = false;
            _isCountdownActive = false;
            _progressValue = 1.0;
          });
        }
        await _guardarLotesDesdeServicio();
        _mostrarMensaje('Alarmas personalizadas completadas y lote guardado.');
      },
    );

    if (newLote != null) {
      List<int> volteadaDurations = [];
      DateTime previousTime = newLote.createdAt;

      for (var volteada in newLote.volteadas) {
        final diferencia = volteada.fechaProgramada.difference(previousTime);
        volteadaDurations.add(diferencia.inHours);
        previousTime = volteada.fechaProgramada;
      }

      _startCountdown(volteadaDurations);

      setState(() {
        _lotesGuardados.add(newLote);
        _isLoading = true;
        _progressValue = 0.0;
      });
      await _guardarLotesDesdeServicio();
    }
  }

  void _verRegistro() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerRegistroScreen(
          loteService: _loteService,
          onLotesChanged: _cargarLotesDesdeServicio,
        ),
      ),
    );
  }

  void _mostrarImagenCalor() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Imagen térmica'),
        content: Image.asset('assets/images/thermal_image.png'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _irAPantallaClima() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ClimaScreen(),
      ),
    );
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          _buildVideoBackground(),
          _buildOverlayContent(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() {}),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildVideoBackground() {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController.value.isInitialized ? _videoController.value.size.width : 0,
          height: _videoController.value.isInitialized ? _videoController.value.size.height : 0,
          child: _videoController.value.isInitialized
              ? VideoPlayer(_videoController)
              : Container(color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildOverlayContent() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 150, height: 150),
            const SizedBox(height: 20),
            const Text(
              'Seed Solution in Engineering',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildProgressIndicator(),
            _buildMainButtons(),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(10.0),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  'Luis_Guererro_CCAV_CUCUTA_UNAD',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    if (_isLoading && _isCountdownActive) {
      return Column(
        children: [
          Text(
            'Ciclo ${_currentCycleIndex + 1} de ${_alarmCycles.length} - Tiempo restante: ${_formatearDuracion(_currentCycleSecondsRemaining)}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _progressValue,
            backgroundColor: Colors.grey,
            color: Colors.red,
          ),
          const SizedBox(height: 20),
        ],
      );
    } else if (_progressValue == 1.0) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Text(
          '¡Proceso de fermentación completado!',
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
      );
    }
    return const SizedBox(height: 20);
  }

  Widget _buildMainButtons() {
    return Column(
      children: [
        ElevatedButton(onPressed: _setPredeterminedAlarm, child: const Text('Alarma Predeterminada')),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _configureCustomAlarm, child: const Text('Configurar Volteadas')),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _mostrarImagenCalor, child: const Text('Imagen de Calor')),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _verRegistro, child: const Text('Ver Registro')),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _irAPantallaClima, child: const Text('🌦️ Ver Clima Actual')),
      ],
    );
  }

  String _formatearDuracion(int totalSegundos) {
    final duracion = Duration(seconds: totalSegundos);
    final horas = duracion.inHours;
    final minutos = duracion.inMinutes.remainder(60);
    final segundos = duracion.inSeconds.remainder(60);
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}';
  }
}

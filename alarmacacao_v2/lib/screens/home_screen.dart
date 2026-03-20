import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/screens/ver_registro_screen.dart';

class HomeScreen extends StatefulWidget {
  final String title;
  final String? notificationPayload;

  const HomeScreen({
    super.key,
    required this.title,
    this.notificationPayload,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LoteService _loteService = LoteService();
  final Uuid _uuid = const Uuid();
  final NotificationService _notificationService = NotificationService();

  final TextEditingController _customLoteTitleController = TextEditingController();
  final List<TextEditingController> _customHourControllers =
      List.generate(5, (_) => TextEditingController());

  List<Lote> _lotesGuardados = [];
  Lote? _currentProcessingLote;
  bool _isLoading = false;
  double _progressValue = 0.0;
  int _counter = 0;

  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _cargarLotesDesdeServicio();
    _inicializarVideo();

    // Muestra mensaje si la app fue abierta por una notificación
    if (widget.notificationPayload != null && widget.notificationPayload!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notificación recibida: ${widget.notificationPayload}'),
            duration: const Duration(seconds: 5),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
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

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _setPredeterminedAlarm() async {
    if (_isLoading) return;

    final nuevoLote = Lote(
      id: _uuid.v4(),
      title: 'Lote Predeterminado ${DateTime.now().hour}:${DateTime.now().minute}',
      volteadas: [],
      status: 'en proceso',
      createdAt: DateTime.now(),
    );

    setState(() {
      _lotesGuardados.add(nuevoLote);
      _currentProcessingLote = nuevoLote;
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
            _progressValue = 0.0;
            _currentProcessingLote = null;
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
        setState(() {
          if (index != -1) {
            _lotesGuardados[index] = completedLote;
          } else {
            _lotesGuardados.add(completedLote);
          }
          _isLoading = false;
          _currentProcessingLote = null;
        });
        await _guardarLotesDesdeServicio();
        _mostrarMensaje('Alarmas personalizadas completadas y lote guardado.');
      },
    );

    if (newLote != null) {
      setState(() {
        _lotesGuardados.add(newLote);
        _currentProcessingLote = newLote;
        _isLoading = true;
      });
      await _guardarLotesDesdeServicio();
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        duration: const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: _isLoading ? LinearProgressIndicator(value: _progressValue) : const SizedBox(),
        ),
      ),
      body: Stack(
        children: [
          _videoController.value.isInitialized
              ? SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController.value.size.width,
                      height: _videoController.value.size.height,
                      child: VideoPlayer(_videoController),
                    ),
                  ),
                )
              : Container(color: Colors.black),
          Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Has presionado el botón $_counter veces',
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _setPredeterminedAlarm,
                    child: const Text('Alarma Predeterminada'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _configureCustomAlarm,
                    child: const Text('Configurar Volteadas'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _mostrarImagenCalor,
                    child: const Text('Imagen de Calor'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _verRegistro,
                    child: const Text('Ver Registro'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        child: const Icon(Icons.add),
      ),
    );
  }
}

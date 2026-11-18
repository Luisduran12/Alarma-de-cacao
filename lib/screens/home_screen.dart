import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/screens/clima_screen.dart';
import 'package:alarmacacao5_0/screens/comparacion_lotes_screen.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/screens/guia_prueba_corte_screen.dart';
import 'package:alarmacacao5_0/screens/reglas_alerta_screen.dart';
import 'package:alarmacacao5_0/screens/ver_registro_screen.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_ids.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';
import 'package:alarmacacao5_0/widgets/timer_progress_bar.dart';

class HomeScreen extends StatefulWidget {
  final String title;
  final String? notificationPayload;

  const HomeScreen({super.key, required this.title, this.notificationPayload});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LoteService _loteService = LoteService();
  final AlarmScheduler _scheduler = AlarmScheduler();

  List<Lote> _lotesEnCurso = [];
  bool _creando = false;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _cargarLotes();
    _inicializarVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _inicializarVideo() async {
    final controller = VideoPlayerController.asset('assets/videos/background_video.mp4');
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (e) {
      debugPrint('No se pudo cargar el video de fondo: $e');
      controller.dispose();
    }
  }

  /// Lotes con ciclo en curso: el progreso sale de la hora de inicio guardada.
  Future<void> _cargarLotes() async {
    final lotes = await _loteService.loadLotes();
    if (!mounted) return;
    setState(() {
      _lotesEnCurso = lotes
          .where((l) => l.status == 'en proceso' && l.inicioCiclo != null && l.finCiclo != null)
          .toList();
    });
  }

  Future<String?> _pedirTitulo(String sugerido) {
    final ctrl = TextEditingController(text: sugerido);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre del lote'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Título del lote'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? sugerido : ctrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _crearConPlantilla(PlantillaCiclo plantilla) async {
    final ahora = DateTime.now();
    final titulo = await _pedirTitulo(
        'Lote ${ahora.day}/${ahora.month} ${ahora.hour}:${ahora.minute.toString().padLeft(2, '0')}');
    if (titulo == null) return;
    await _crear(() => _scheduler.crearLote(titulo: titulo, plantilla: plantilla));
  }

  Future<void> _crearPersonalizado() async {
    await _crear(() => _scheduler.crearLotePersonalizado(context));
  }

  Future<void> _crear(Future<Lote?> Function() accion) async {
    setState(() => _creando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final lote = await accion();
      if (lote != null) {
        final alarmas = lote.volteadas.length;
        messenger.showSnackBar(SnackBar(
          content: Text('Lote "${lote.title}" creado con $alarmas alarmas programadas.'),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo crear el lote: $e')));
    } finally {
      if (mounted) setState(() => _creando = false);
      await _cargarLotes();
    }
  }

  /// Alarma de prueba en 10 segundos: sirve para comprobar el sonido y que
  /// la alarma llega con la app cerrada.
  Future<void> _probarAlarma() async {
    await NotificationService().programarNotificacion(
      id: await NotificationIds.siguiente(),
      titulo: 'Alarma de prueba',
      cuerpo: 'Si escuchas esto, las alarmas de volteo funcionan.',
      fechaProgramada: DateTime.now().add(const Duration(seconds: 10)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Alarma de prueba en 10 segundos. Puedes cerrar la app para comprobarla.'),
    ));
  }

  Future<void> _abrir(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
    await _cargarLotes();
  }

  void _mostrarImagenCalor() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Imagen térmica'),
        content: Image.asset('assets/images/thermal_image.png'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Probar alarma (10 s)',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: _probarAlarma,
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildFondo(),
          Container(color: Colors.black54),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _cargarLotes,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(child: Image.asset('assets/images/logo.png', width: 120, height: 120)),
                  const SizedBox(height: 8),
                  const Text(
                    'Seed Solution in Engineering',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ..._buildLotesEnCurso(),
                  _buildBotones(),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      'Luis_Guererro_CCAV_CUCUTA_UNAD',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_creando)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildFondo() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return Container(color: Colors.brown.shade900);
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      ),
    );
  }

  List<Widget> _buildLotesEnCurso() {
    if (_lotesEnCurso.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'No hay lotes en curso. Crea uno para programar las alarmas de volteo.',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      const Text('Lotes en curso',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      for (final lote in _lotesEnCurso)
        Card(
          color: Colors.white.withValues(alpha: 0.92),
          child: InkWell(
            onTap: () => _abrir(DetalleLoteScreen(lote: lote)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lote.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    '${Plantillas.nombre(lote.plantilla)} · '
                    '${lote.volteadas.where((v) => v.confirmada).length}/${lote.volteadas.length} registros',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TimerProgressBar(
                    inicio: lote.inicioCiclo!,
                    fin: lote.finCiclo!,
                    progressColor: Colors.brown,
                  ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildBotones() {
    Widget boton(IconData icono, String texto, VoidCallback? accion) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ElevatedButton.icon(
            onPressed: _creando ? null : accion,
            icon: Icon(icono),
            label: Text(texto),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        );

    return Column(
      children: [
        boton(Icons.timer, 'Plantilla fermentación 144 h', () => _crearConPlantilla(Plantillas.fedecacao144)),
        boton(Icons.alarm, 'Alarma predeterminada (24-34-48 h)',
            () => _crearConPlantilla(Plantillas.predeterminada)),
        boton(Icons.tune, 'Configurar volteadas', _crearPersonalizado),
        boton(Icons.list_alt, 'Ver registro', () => _abrir(VerRegistroScreen(
              loteService: _loteService,
              onLotesChanged: _cargarLotes,
            ))),
        boton(Icons.compare_arrows, 'Comparar lotes', () => _abrir(const ComparacionLotesScreen())),
        boton(Icons.content_cut, 'Guía de la prueba de corte', () => _abrir(const GuiaPruebaCorteScreen())),
        boton(Icons.notifications_active, 'Alertas por reglas', () => _abrir(const ReglasAlertaScreen())),
        boton(Icons.cloud, 'Ver clima actual', () => _abrir(const ClimaScreen())),
        boton(Icons.thermostat, 'Imagen de calor', _mostrarImagenCalor),
      ],
    );
  }
}

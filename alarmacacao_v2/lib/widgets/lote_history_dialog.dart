// main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // Importa para codificar/decodificar JSON
import 'package:uuid/uuid.dart'; // Importa para generar IDs únicos
import 'package:video_player/video_player.dart'; // Importa para reproducir video
import 'package:flutter/services.dart'; // Para FilteringTextInputFormatter

// Clase para representar un Lote de volteadas
class Lote {
  final String id;
  String title;
  List<String> volteadas;
  String status; // Ej: "en proceso", "completado"
  final DateTime createdAt;

  Lote({
    required this.id,
    required this.title,
    required this.volteadas,
    required this.status,
    required this.createdAt,
  });

  // Método para convertir un objeto Lote a un mapa (para JSON)
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'volteadas': volteadas,
        'status': status,
        'createdAt': createdAt.toIso8601String(), // Guarda la fecha como string ISO 8601
      };

  // Constructor factory para crear un objeto Lote desde un mapa (JSON)
  factory Lote.fromJson(Map<String, dynamic> json) => Lote(
        id: json['id'],
        title: json['title'],
        volteadas: List<String>.from(json['volteadas']),
        status: json['status'],
        createdAt: DateTime.parse(json['createdAt']), // Convierte el string de vuelta a DateTime
      );
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'hola flluter'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  bool _isLoading = false;
  double _progressValue = 0.0;
  List<Lote> _lotesGuardados = []; // Ahora guarda una lista de objetos Lote
  Lote? _currentProcessingLote; // Para referenciar el lote actual en proceso
  final Uuid _uuid = const Uuid(); // Instancia para generar IDs únicos

  late VideoPlayerController _videoController; // Controlador de Video

  // Controladores para los campos de texto del diálogo de horas (para la nueva lógica)
  final TextEditingController _customLoteTitleController = TextEditingController();
  final List<TextEditingController> _customHourControllers =
      List.generate(5, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _cargarLotes();
    _initializeVideoPlayer(); // Inicializa el reproductor de video
  }

  // Método para inicializar el video
  void _initializeVideoPlayer() {
    _videoController = VideoPlayerController.asset('assets/videos/background_video.mp4') // <-- ¡Tu video de fondo!
      ..initialize().then((_) {
        // Asegúrate de que el primer frame esté listo y el estado sea actualizado
        if (mounted) { // Verificar si el widget sigue montado antes de llamar a setState
          setState(() {});
        }
        _videoController.setLooping(true); // El video se repetirá
        _videoController.setVolume(0.0); // Sin volumen para video de fondo
        _videoController.play(); // Inicia la reproducción
      });
  }

  @override
  void dispose() {
    _videoController.dispose(); // Importante: Libera los recursos del video al destruir el widget
    _customLoteTitleController.dispose();
    for (var controller in _customHourControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarLotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? lotesJson = prefs.getString('lotes_data');
      if (lotesJson != null) {
        final List<dynamic> jsonList = jsonDecode(lotesJson);
        setState(() {
          _lotesGuardados = jsonList.map((json) => Lote.fromJson(json)).toList();
          // Ordenar por fecha de creación (los más recientes primero)
          _lotesGuardados.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      }
      print('DEBUG: Lotes cargados al iniciar: ${_lotesGuardados.length} lotes.');
    } catch (e) {
      print('ERROR al cargar lotes: $e');
    }
  }

  Future<void> _guardarLotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = _lotesGuardados.map((lote) => lote.toJson()).toList();
      await prefs.setString('lotes_data', jsonEncode(jsonList));
      print('DEBUG: Lotes guardados: ${_lotesGuardados.length} lotes.');
    } catch (e) {
      print('ERROR al guardar lotes: $e');
    }
  }

  Future<void> _deleteLote(String loteId) async {
    setState(() {
      _lotesGuardados.removeWhere((lote) => lote.id == loteId);
    });
    await _guardarLotes();
    print('DEBUG: Lote con ID $loteId eliminado.');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lote eliminado correctamente.')),
    );
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  // --- LÓGICA ORIGINAL PARA EL BOTÓN "ALARMA PREDETERMINADA" ---
  // Esta función simula un set fijo de 5 volteadas.
  Future<void> _setPredeterminedAlarm() async {
    if (_isLoading) return; // Evitar múltiples simulaciones a la vez

    String loteTitle = 'Lote Predeterminado ${DateTime.now().hour}:${DateTime.now().minute}';

    _currentProcessingLote = Lote(
      id: _uuid.v4(),
      title: loteTitle,
      volteadas: [],
      status: 'en proceso',
      createdAt: DateTime.now(),
    );

    setState(() {
      _lotesGuardados.add(_currentProcessingLote!);
      _isLoading = true;
      _progressValue = 0.0;
    });
    await _guardarLotes();

    const int totalVolteadas = 5;
    const int simulatedDelayPerVolteadaSeconds = 3;

    for (int i = 0; i < totalVolteadas; i++) {
      int hoursFromStart = 48 + (i * 24); // Ejemplo: 48h, 72h, 96h...
      String message = 'Volteada ${i + 1} (simulada a las $hoursFromStart horas)';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: simulatedDelayPerVolteadaSeconds),
        ),
      );

      setState(() {
        final index = _lotesGuardados.indexWhere((l) => l.id == _currentProcessingLote!.id);
        if (index != -1) {
          _lotesGuardados[index].volteadas.add(message);
        }
      });
      await _guardarLotes();

      setState(() {
        _progressValue = (i + 1) / totalVolteadas.toDouble();
      });

      await Future.delayed(const Duration(seconds: simulatedDelayPerVolteadaSeconds));
    }

    // Finalizar el lote
    setState(() {
      final index = _lotesGuardados.indexWhere((l) => l.id == _currentProcessingLote!.id);
      if (index != -1) {
        _lotesGuardados[index].status = 'completado';
      }
      _isLoading = false;
      _progressValue = 0.0;
      _currentProcessingLote = null;
    });
    await _guardarLotes();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulación de alarmas predeterminadas completada y lote guardado.'),
        duration: Duration(seconds: 2),
      ),
    );
  }


  // --- NUEVA LÓGICA PARA EL BOTÓN "CONFIGURAR VOLTEADAS" ---
  // Esta función permite al usuario ingresar 5 horas personalizadas.
  Future<void> _configureCustomAlarm() async {
    if (_isLoading) return; // Evitar múltiples simulaciones a la vez

    // Reiniciar controladores de texto con valores por defecto
    _customLoteTitleController.text = 'Lote Personalizado ${DateTime.now().hour}:${DateTime.now().minute}';
    for (var controller in _customHourControllers) {
      controller.text = ''; // Limpiar campos de horas
    }

    List<int>? inputHours = await showDialog<List<int>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Configurar Nuevo Lote de Volteadas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _customLoteTitleController,
                  decoration: const InputDecoration(
                    labelText: 'Título del Lote',
                    hintText: 'Ej: Lote Mañana, Lote Especial',
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Ingrese 5 valores de horas para las volteadas (0 para ignorar):'),
                ...List.generate(5, (index) => TextField(
                  controller: _customHourControllers[index],
                  keyboardType: TextInputType.number,
                  // Permite solo dígitos numéricos
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Volteada ${index + 1} (horas)',
                  ),
                )),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext).pop(null); // Retorna null si se cancela
              },
            ),
            ElevatedButton(
              child: const Text('Iniciar Simulación'),
              onPressed: () {
                List<int> parsedHours = [];
                bool hasError = false;
                for (var controller in _customHourControllers) {
                  final text = controller.text;
                  if (text.isEmpty) {
                    parsedHours.add(0); // Tratar campo vacío como 0 (ignorar)
                  } else {
                    final value = int.tryParse(text);
                    if (value == null || value < 0) { // Validar que sea número entero no negativo
                      hasError = true;
                      ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Por favor, ingrese solo números enteros positivos para las horas.')),
                      );
                      break; // Salir del bucle en el primer error
                    }
                    parsedHours.add(value);
                  }
                }

                if (hasError) return; // No proceder si hubo un error de parsing

                Navigator.of(dialogContext).pop(parsedHours); // Retorna la lista de horas
              },
            ),
          ],
        );
      },
    );

    // Si el diálogo fue cancelado o no se ingresaron horas
    if (inputHours == null) {
      print('DEBUG: Creación de lote cancelada.');
      return;
    }

    // Filtrar las horas que sean mayores a 0
    List<int> validHours = inputHours.where((h) => h > 0).toList();

    if (validHours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se ingresaron horas válidas (> 0) para simular.')),
      );
      print('DEBUG: No se encontraron horas válidas para simular.');
      return;
    }

    // Usar el título del controlador, si está vacío, asignar uno por defecto
    String loteTitle = _customLoteTitleController.text.trim().isEmpty
        ? 'Lote sin Título'
        : _customLoteTitleController.text.trim();


    // Crear el nuevo lote y añadirlo a la lista
    _currentProcessingLote = Lote(
      id: _uuid.v4(), // Generar un ID único
      title: loteTitle,
      volteadas: [],
      status: 'en proceso',
      createdAt: DateTime.now(),
    );

    setState(() {
      _lotesGuardados.add(_currentProcessingLote!);
      _isLoading = true;
      _progressValue = 0.0;
    });
    await _guardarLotes(); // Guardar el lote inicial con estado "en proceso"

    final int totalValidVolteadas = validHours.length;
    const int simulatedDelayPerVolteadaSeconds = 3;

    for (int i = 0; i < totalValidVolteadas; i++) {
      int currentHour = validHours[i];
      String message = 'Volteada ${i + 1} (simulada a las $currentHour horas)';

      print('DEBUG: Mensaje de SnackBar: $message');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: simulatedDelayPerVolteadaSeconds),
        ),
      );

      // Añadir la volteada al lote actual y guardar
      setState(() {
        // Asegurarse de que estamos modificando el lote correcto en la lista _lotesGuardados
        // y no solo la copia _currentProcessingLote
        final index = _lotesGuardados.indexWhere((l) => l.id == _currentProcessingLote!.id);
        if (index != -1) {
          _lotesGuardados[index].volteadas.add(message);
        }
      });
      await _guardarLotes(); // Guardar los lotes después de cada volteada

      // Actualizar la barra de progreso
      setState(() {
        _progressValue = (i + 1) / totalValidVolteadas.toDouble();
      });

      await Future.delayed(const Duration(seconds: simulatedDelayPerVolteadaSeconds));
    }

    // Finalizar el lote
    setState(() {
      final index = _lotesGuardados.indexWhere((l) => l.id == _currentProcessingLote!.id);
      if (index != -1) {
        _lotesGuardados[index].status = 'completado';
      }
      _isLoading = false;
      _progressValue = 0.0;
      _currentProcessingLote = null; // Limpiar la referencia al lote en proceso
    });
    await _guardarLotes(); // Guardar el lote con estado "completado"

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulación de alarmas personalizadas completada y lote guardado.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
  // --- FIN DE LÓGICA DEL NUEVO BOTÓN ---


  void _viewHistory() {
    print('DEBUG: Botón Ver Historial presionado!');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mostrando historial de lotes...'),
        duration: Duration(seconds: 2),
      ),
    );

    print('DEBUG: Lotes guardados para mostrar: ${_lotesGuardados.length}');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Historial de Lotes de Volteadas'),
          content: _lotesGuardados.isEmpty
              ? const Text('No hay lotes guardados aún. Presiona "Alarma Predeterminada" o "Configurar Volteadas" para generar un nuevo lote.')
              : SizedBox(
                  width: double.maxFinite, // Permite que el diálogo sea más ancho si es necesario
                  child: ListView.builder(
                    shrinkWrap: true, // Ajusta la altura al contenido
                    itemCount: _lotesGuardados.length,
                    itemBuilder: (context, index) {
                      final lote = _lotesGuardados[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
                        child: ListTile(
                          title: Text(lote.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Estado: ${lote.status == 'en proceso' ? 'En Proceso' : 'Completado'}'),
                              Text('Creado: ${lote.createdAt.toLocal().toString().split('.')[0]}'), // Formato legible
                              Text('Volteadas: ${lote.volteadas.length}'),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              // Confirmar eliminación
                              final bool confirmDelete = await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text('Confirmar Eliminación'),
                                    content: Text('¿Estás seguro de que quieres eliminar el lote "${lote.title}"?'),
                                    actions: <Widget>[
                                      TextButton(
                                        child: const Text('Cancelar'),
                                        onPressed: () {
                                          Navigator.of(context).pop(false); // No eliminar
                                        },
                                      ),
                                      ElevatedButton(
                                        child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                        onPressed: () {
                                          Navigator.of(context).pop(true); // Confirmar eliminación
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ) ?? false; // Valor por defecto si se cierra el diálogo

                              if (confirmDelete) {
                                Navigator.of(context).pop(); // Cierra el diálogo actual de historial
                                await _deleteLote(lote.id); // Elimina el lote
                                // Vuelve a abrir el historial para mostrar el cambio
                                _viewHistory(); // Recarga el historial para que el cambio se refleje
                              }
                            },
                          ),
                          onTap: () {
                            // Mostrar detalles de las volteadas del lote
                            _showLoteDetails(lote); // <-- Aquí es donde se llama a la función
                          },
                        ),
                      );
                    },
                  ),
                ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cerrar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // --- DEFINICIÓN DE _showLoteDetails ---
  void _showLoteDetails(Lote lote) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Detalles del Lote: ${lote.title}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${lote.id}'),
                Text('Estado: ${lote.status == 'en proceso' ? 'En Proceso' : 'Completado'}'),
                Text('Creado: ${lote.createdAt.toLocal().toString().split('.')[0]}'),
                const Divider(),
                const Text('Volteadas:', style: TextStyle(fontWeight: FontWeight.bold)),
                if (lote.volteadas.isEmpty)
                  const Text('No hay volteadas registradas para este lote aún.')
                else
                  ...lote.volteadas.map((item) => Text('- $item')).toList(),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cerrar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showHeatmapImage() async {
    print('Imagen de calor presionado!');
    setState(() {
      _isLoading = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isLoading = false;
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Imagen de Calor'),
          content: SingleChildScrollView(
            child: Image.asset(
              'assets/images/thermal_image.png', // Asegúrate que la extensión sea la correcta (.png o .jpg)
              fit: BoxFit.contain,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cerrar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: _isLoading
              ? LinearProgressIndicator(value: _progressValue)
              : Container(),
        ),
      ),
      // --- Stack para el video de fondo y el contenido principal ---
      body: Stack(
        children: <Widget>[
          // Fondo de video
          // Solo muestra el VideoPlayer si el controlador está inicializado
          _videoController.value.isInitialized
              ? SizedBox.expand( // Asegura que el video ocupe todo el espacio disponible
                  child: FittedBox(
                    fit: BoxFit.cover, // Cubre todo el espacio sin distorsionar la relación de aspecto
                    child: SizedBox(
                      width: _videoController.value.size.width,
                      height: _videoController.value.size.height,
                      child: VideoPlayer(_videoController),
                    ),
                  ),
                )
              : Container(color: Colors.black), // Muestra un fondo negro mientras el video carga

          // Contenido principal de la aplicación (encima del video)
          // Usamos un 'Container' o 'Positioned.fill' con un color semi-transparente
          // para mejorar la legibilidad del texto sobre el video.
          // Puedes ajustar el color y la opacidad (ej. Colors.black54)
          Container(
            color: Colors.black54, // Capa semi-transparente para mejorar contraste
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // Texto para que sea visible sobre el video oscuro
                  const Text(
                    'You have pushed the button this many times:',
                    style: TextStyle(color: Colors.white70), // Texto más claro
                  ),
                  Text(
                    '$_counter',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white), // Texto más claro
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _setPredeterminedAlarm, // <--- Botón "Alarma Predeterminada" con su lógica original
                    child: const Text('Alarma Predeterminada'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _configureCustomAlarm, // <--- ¡NUEVO BOTÓN con la lógica de las 5 entradas!
                    child: const Text('Configurar Volteadas'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _viewHistory,
                    child: const Text('Ver Historial'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _showHeatmapImage,
                    child: const Text('Imagen de Calor'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
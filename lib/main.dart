import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// Servicios
import 'package:alarmacacao5_0/services/notification_service.dart';


// Pantallas
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/clima_cacao_page.dart';
import 'package:alarmacacao5_0/screens/configurar_lote_screen.dart';
import 'package:alarmacacao5_0/screens/guia_prueba_corte_screen.dart';
import 'package:alarmacacao5_0/screens/permisos_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  await _solicitarPermisos();
  await NotificationService().init(); // Inicializa notificaciones
  await NotificationService().solicitarPermisos(); // Notificaciones + alarmas exactas

  // Si la app se abrió tocando una notificación con la app cerrada,
  // se abre el formulario de esa volteada cuando el Navigator esté listo.
  final argsLanzamiento = await NotificationService().argumentosDeLanzamiento();

  runApp(const MyApp());

  if (argsLanzamiento != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.pushNamed(
        argsLanzamiento['ruta'] ?? NotificationService.rutaConfirmar,
        arguments: argsLanzamiento,
      );
    });
  }
}

/// Solo se pide la ubicación MIENTRAS SE USA la app (para el clima y para
/// marcar el punto de secado). La ubicación en segundo plano no se necesita
/// y Google Play rechaza apps que la piden sin justificación.
Future<void> _solicitarPermisos() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await [
      Permission.notification,
      Permission.locationWhenInUse,
    ].request();
  }
}

class MyApp extends StatelessWidget {
  final String? notificationPayload;

  const MyApp({super.key, this.notificationPayload});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cacao Light 4.0',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: const PermisosScreen(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/clima':
            return MaterialPageRoute(builder: (_) => const ClimaCacaoPage());
          case '/configurar':
            return MaterialPageRoute(builder: (_) => const ConfigurarLoteScreen());
          case '/guia-corte':
            final args = settings.arguments;
            if (args is Map && args['loteId'] is String) {
              return MaterialPageRoute(
                builder: (_) => GuiaPruebaCorteScreen(
                  loteId: args['loteId'] as String,
                  volteadaId: (args['volteadaId'] as String?) ?? '',
                ),
              );
            }
            return MaterialPageRoute(builder: (_) => const GuiaPruebaCorteScreen());
          case '/confirmar':
            final args = settings.arguments;
            if (args is Map && args['loteId'] is String) {
              return MaterialPageRoute(
                builder: (_) => ConfirmarVolteadaScreen(
                  loteId: args['loteId'] as String,
                  volteadaId: (args['volteadaId'] as String?) ?? '',
                  mensaje: (args['mensaje'] as String?) ?? '',
                ),
              );
            } else {
              return MaterialPageRoute(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('Argumentos inválidos')),
                ),
              );
            }
          default:
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text('Ruta no encontrada')),
              ),
            );
        }
      },
    );
  }
}

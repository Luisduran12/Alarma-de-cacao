import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// Servicios
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/volteada_service.dart';

// Modelos
import 'package:alarmacacao5_0/models/volteada.dart';

// Pantallas
import 'package:alarmacacao5_0/screens/home_screen.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/clima_cacao_page.dart';
import 'package:alarmacacao5_0/screens/configurar_lote_screen.dart';
import 'package:alarmacacao5_0/screens/permisos_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  await _solicitarPermisos();
  await NotificationService().init(); // Inicializa notificaciones

  runApp(const MyApp());
}

Future<void> _solicitarPermisos() async {
  if (Platform.isAndroid) {
    await [
      Permission.notification,
      Permission.scheduleExactAlarm,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();
  } else if (Platform.isIOS) {
    await [
      Permission.notification,
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();
  }
}

class MyApp extends StatelessWidget {
  final String? notificationPayload;

  const MyApp({super.key, this.notificationPayload});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alarma Cacao 5.0',
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
            return MaterialPageRoute(builder: (_) => ConfigurarLoteScreen());
          case '/confirmar':
            final args = settings.arguments;
            if (args is Map<String, dynamic> &&
                args.containsKey('loteId') &&
                args.containsKey('mensaje')) {
              return MaterialPageRoute(
                builder: (_) => ConfirmarVolteadaScreen(
                  loteId: args['loteId'],
                  mensaje: args['mensaje'],
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

@pragma('vm:entry-point')
void callbackDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  final volteadaService = VolteadaService();
  final notificationService = NotificationService();

  final List<Volteada> volteadas = await volteadaService.cargarVolteadas();

  for (final volteada in volteadas) {
    if (!volteada.confirmada) {
      await notificationService.programarNotificacion(
        id: volteada.id.hashCode,
        titulo: 'Recordatorio de volteada',
        cuerpo: 'Voltea el cacao del lote ${volteada.loteId}',
        fechaProgramada: volteada.fechaProgramada,
        payload:
            '${volteada.loteId}|Volteada pendiente|${volteada.mensaje}|${volteada.fechaProgramada.toIso8601String()}',
      );
    }
  }
}

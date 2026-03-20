import 'dart:io';

import 'package:flutter/material.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/screens/home_screen.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/services/volteada_service.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // Solicita permisos antes de inicializar el servicio
  await _solicitarPermisos();

  // Inicializa el servicio de notificaciones
  NotificationService();

  runApp(const MyApp());
}

Future<void> _solicitarPermisos() async {
  final notificationStatus = await Permission.notification.status;
  if (notificationStatus.isDenied || notificationStatus.isPermanentlyDenied) {
    await Permission.notification.request();
  }

  final alarmStatus = await Permission.scheduleExactAlarm.status;
  if (alarmStatus.isDenied || alarmStatus.isPermanentlyDenied) {
    await Permission.scheduleExactAlarm.request();
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/confirmar') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ConfirmarVolteadaScreen(
              loteId: args['loteId'],
              mensaje: args['mensaje'],
            ),
          );
        }
        return null;
      },
      home: HomeScreen(
        title: 'Alarma Cacao',
        notificationPayload: notificationPayload,
      ),
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
 
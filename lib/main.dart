import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// Servicios
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lugar_service.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/preferencias_app.dart';
import 'package:alarmacacao5_0/tema_app.dart';

// Pantallas
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/configurar_lote_screen.dart';
import 'package:alarmacacao5_0/screens/guia_prueba_corte_screen.dart';
import 'package:alarmacacao5_0/screens/permisos_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await PreferenciasApp.cargar();

  await _solicitarPermisos();
  await NotificationService().init(); // Inicializa notificaciones
  await NotificationService()
      .solicitarPermisos(); // Notificaciones + alarmas exactas

  // Red de seguridad: si el sistema perdió alguna alarma (por ejemplo, un ahorrador
  // de batería bloqueó el reinicio de alarmas), se reprograma. No retrasa el arranque.
  unawaited(_reprogramarAlarmasPerdidas());

  // Si hay señal y un servidor configurado, se resuelven los nombres de lugar
  // que faltan (sin servidor no hace nada: la lista offline basta).
  // Con el ahorro de batería no se hace por su cuenta.
  if (!PreferenciasApp.instancia.ahorroBateria) unawaited(_resolverLugaresPendientes());

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

Future<void> _reprogramarAlarmasPerdidas() async {
  try {
    final pendientes = (await NotificationService().getPendingNotifications())
        .map((p) => p.id)
        .toSet();
    final n = await AlarmScheduler().reprogramarFaltantes(pendientes);
    if (n > 0) {
      debugPrint('🔁 Se reprogramaron $n alarmas que el sistema había perdido');
    }
  } catch (e) {
    debugPrint('No se pudieron revisar las alarmas pendientes: $e');
  }
}

Future<void> _resolverLugaresPendientes() async {
  try {
    final n = await LugarService().resolverPendientes();
    if (n > 0) debugPrint('📍 Se resolvieron $n nombres de lugar');
  } catch (e) {
    debugPrint('No se pudieron resolver los nombres de lugar: $e');
  }
}

/// Solo se pide la ubicación MIENTRAS SE USA la app (para el clima y para
/// marcar el punto de secado). La ubicación en segundo plano no se necesita
/// y Google Play rechaza apps que la piden sin justificación.
/// La ubicación NO se pide aquí: se pide en PermisosScreen, después de explicarla y de que el productor acepte.
Future<void> _solicitarPermisos() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Permission.notification.request();
  }
}

class MyApp extends StatelessWidget {
  final String? notificationPayload;

  const MyApp({super.key, this.notificationPayload});

  @override
  Widget build(BuildContext context) {
    final prefs = PreferenciasApp.instancia;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'Cacao Light 4.0',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: TemaApp.construir(altoContraste: prefs.altoContraste),
        builder: (context, hijo) =>
            TemaApp.conPreferencias(context, hijo, prefs),
        home: const PermisosScreen(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/configurar':
              return MaterialPageRoute(
                builder: (_) => const ConfigurarLoteScreen(),
              );
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
              return MaterialPageRoute(
                builder: (_) => const GuiaPruebaCorteScreen(),
              );
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
      ),
    );
  }
}

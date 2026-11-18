import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:alarmacacao5_0/main.dart'; // Para navigatorKey

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('🔔 Tocada notificación en segundo plano. Payload: ${notificationResponse.payload}');
  NotificationService._handleNotificationResponse(notificationResponse);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  Future<void> init() async {
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    debugPrint('✅ Servicio de notificaciones inicializado correctamente');
  }

  /// Pide permiso de notificaciones (Android 13+) y de alarmas exactas (Android 12+).
  Future<void> solicitarPermisos() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    if (!(await android?.canScheduleExactNotifications() ?? true)) {
      await android?.requestExactAlarmsPermission();
    }
  }

  /// Payload de una volteada: "v2|<loteId>|<volteadaId>".
  static String payloadVolteada(String loteId, String volteadaId) => 'v2|$loteId|$volteadaId';

  /// Payload de un recordatorio de medir la temperatura: "m|<loteId>".
  static String payloadMedir(String loteId) => 'm|$loteId';

  /// Payload del aviso de fin de fermentación: "c|<loteId>|<volteadaId>". Abre
  /// la guía de la prueba de corte.
  static String payloadCorte(String loteId, String volteadaId) => 'c|$loteId|$volteadaId';

  static const rutaConfirmar = '/confirmar';
  static const rutaGuiaCorte = '/guia-corte';

  /// Convierte un payload en argumentos para abrir una pantalla.
  /// Acepta "v2|lote|volteada" (volteada), "m|lote" (medir temperatura: registro
  /// nuevo), "c|lote|volteada" (guía de la prueba de corte) y el formato antiguo
  /// "loteId|titulo|mensaje|fecha". Los tipos nuevos traen la clave `ruta`; sin
  /// ella la pantalla es '/confirmar'.
  static Map<String, String>? argumentosDesdePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    final parts = payload.split('|');
    if (parts.length == 3 && parts[0] == 'v2') {
      return {'loteId': parts[1], 'volteadaId': parts[2], 'mensaje': ''};
    }
    if (parts.length == 2 && parts[0] == 'm' && parts[1].isNotEmpty) {
      return {'loteId': parts[1], 'volteadaId': '', 'mensaje': '', 'ruta': rutaConfirmar};
    }
    if (parts.length == 3 && parts[0] == 'c' && parts[1].isNotEmpty) {
      return {'loteId': parts[1], 'volteadaId': parts[2], 'mensaje': '', 'ruta': rutaGuiaCorte};
    }
    if (parts.length >= 4) {
      return {'loteId': parts[0], 'volteadaId': '', 'mensaje': parts[2]};
    }
    return null;
  }

  /// Al tocar la notificación SOLO se abre el formulario de confirmación.
  /// Antes, además de abrir el formulario, se guardaba aquí una volteada
  /// "confirmada" vacía, y el formulario guardaba otra: registros duplicados.
  static Future<void> _handleNotificationResponse(NotificationResponse response) async {
    final args = argumentosDesdePayload(response.payload);
    if (args == null) {
      debugPrint('⚠️ Payload no reconocido: ${response.payload}');
      return;
    }
    navigatorKey.currentState?.pushNamed(args['ruta'] ?? rutaConfirmar, arguments: args);
  }

  /// Si la app se abrió desde una notificación (estando cerrada), devuelve
  /// los argumentos para abrir el formulario de esa volteada.
  Future<Map<String, String>?> argumentosDeLanzamiento() async {
    final details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return argumentosDesdePayload(details!.notificationResponse?.payload);
    }
    return null;
  }

  /// Mostrar una notificación inmediata
  Future<void> mostrarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'instant_channel',
      'Notificaciones Instantáneas',
      channelDescription: 'Canal para notificaciones inmediatas',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('sonido_base'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'sonido_base.mp3',
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      titulo,
      cuerpo,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  /// Programar notificación con tiempo exacto
  Future<void> programarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime fechaProgramada,
    String? payload,
    bool esRecordatorio = false,
  }) async {
    final fechaZoned = tz.TZDateTime.from(fechaProgramada, tz.local);

    // Los recordatorios de medir la temperatura van en su propio canal: así el
    // productor puede silenciarlos desde los ajustes de Android sin perder las alarmas de volteo.
    final androidDetails = esRecordatorio
        ? const AndroidNotificationDetails(
            'recordatorios_channel',
            'Recordatorios de medición',
            channelDescription: 'Avisos de medir la temperatura de la masa cada 12 horas',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('sonido_base'),
          )
        : const AndroidNotificationDetails(
            'volteadas_channel',
            'Alarmas Programadas',
            channelDescription: 'Canal para notificaciones programadas',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('sonido_base'),
          );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'sonido_base.mp3',
    );

    if (fechaZoned.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('⚠️ Fecha en el pasado, no se programa: $fechaZoned');
      return;
    }

    // Si Android no concede alarmas exactas (Android 12+), se usa una inexacta
    // en vez de fallar.
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final bool puedeExacta = await android?.canScheduleExactNotifications() ?? true;

    // Sin matchDateTimeComponents: con DateTimeComponents.dateAndTime la alarma
    // se repetía cada año. Esta es una alarma de una sola vez.
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      fechaZoned,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: puedeExacta
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );

    debugPrint('📅 Notificación programada para $fechaZoned con ID $id');
  }

  /// Cancelar una notificación específica
  Future<void> cancelarNotificacion(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint('🗑️ Notificación cancelada: ID $id');
  }

  /// Cancelar todas las notificaciones
  Future<void> cancelarTodasLasNotificaciones() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('🗑️ Todas las notificaciones canceladas');
  }

  /// Ver notificaciones pendientes
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }
}

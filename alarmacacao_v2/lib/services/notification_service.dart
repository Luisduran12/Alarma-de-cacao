import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/main.dart'; // navigatorKey

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final LoteService _globalLoteService = LoteService();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint('🔔 Tocada notificación en segundo plano. Payload: ${notificationResponse.payload}');
  NotificationService._handleNotificationResponse(notificationResponse);
}

class NotificationService {
  NotificationService() {
    _initializeNotifications();
  }

  void _initializeNotifications() async {
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
  }

  /// Manejo de respuesta a notificación
  static Future<void> _handleNotificationResponse(NotificationResponse notificationResponse) async {
    final String? payload = notificationResponse.payload;

    if (payload == null || payload.isEmpty) {
      debugPrint('⚠️ Payload vacío');
      return;
    }

    final parts = payload.split('|');
    if (parts.length < 4) {
      debugPrint('⚠️ Payload incompleto: $payload');
      return;
    }

    final String loteId = parts[0];
    final String loteTitle = parts[1];
    final String message = parts[2];
    final String fechaStr = parts[3];

    DateTime fechaProgramada = DateTime.tryParse(fechaStr) ?? DateTime.now();

    navigatorKey.currentState?.pushNamed(
      '/confirmar',
      arguments: {
        'loteId': loteId,
        'mensaje': message,
      },
    );

    List<Lote> allLotes = await _globalLoteService.loadLotes();
    final index = allLotes.indexWhere((l) => l.id == loteId);

    if (index != -1) {
      Lote lote = allLotes[index];
      final List<Volteada> nuevasVolteadas = List<Volteada>.from(lote.volteadas ?? []);

      final bool yaExiste = nuevasVolteadas.any((v) => v.mensaje == message);
      if (!yaExiste) {
        nuevasVolteadas.add(
          Volteada(
            id: const Uuid().v4(),
            loteId: loteId,
            mensaje: message,
            temperatura: 0.0,
            humedad: 0.0,
            observacion: '',
            fecha: DateTime.now(),
            fechaProgramada: fechaProgramada,
            confirmada: true,
          ),
        );

        final loteActualizado = lote.copyWith(volteadas: nuevasVolteadas);
        allLotes[index] = loteActualizado;
        await _globalLoteService.saveLotes(allLotes);

        debugPrint('✅ Lote actualizado: ${lote.title} ($loteId) → $message');
      } else {
        debugPrint('⚠️ Volteada ya registrada: "$message" en lote $loteId.');
      }
    } else {
      debugPrint('❌ Lote ID no encontrado: $loteId');
    }
  }

  /// Mostrar notificación instantánea
  Future<void> mostrarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'instant_channel',
      'Notificaciones Instantáneas',
      channelDescription: 'Canal para mostrar notificaciones al instante',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      id,
      titulo,
      cuerpo,
      platformDetails,
      payload: payload,
    );
  }

  /// Programar notificación para una fecha y hora exacta
  Future<void> programarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime fechaProgramada,
    String? payload,
  }) async {
    tz_data.initializeTimeZones();
    final tz.TZDateTime fechaZoned = tz.TZDateTime.from(fechaProgramada, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'scheduled_channel_id',
      'Alarmas Programadas',
      channelDescription: 'Notificaciones programadas con fecha y hora exacta',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      fechaZoned,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
      payload: payload,
    );

    debugPrint('✅ Notificación programada: $fechaZoned con ID $id');
  }

  /// Cancelar una notificación por ID
  Future<void> cancelarNotificacion(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint('❌ Notificación cancelada: ID $id');
  }

  /// Cancelar todas las notificaciones programadas
  Future<void> cancelarTodasLasNotificaciones() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('❌ Todas las notificaciones han sido canceladas.');
  }

  /// Obtener notificaciones pendientes
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await flutterLocalNotificationsPlugin.pendingNotificationRequests();
  }
}

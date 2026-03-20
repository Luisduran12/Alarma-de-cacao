import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/main.dart'; // Para navigatorKey

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final LoteService _globalLoteService = LoteService();

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

  /// Manejo de respuesta cuando el usuario toca una notificación
  static Future<void> _handleNotificationResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) {
      debugPrint('⚠️ Payload vacío');
      return;
    }

    final parts = payload.split('|');
    if (parts.length < 4) {
      debugPrint('⚠️ Payload incompleto: $payload');
      return;
    }

    final loteId = parts[0];
    final loteTitle = parts[1];
    final mensaje = parts[2];
    final fechaStr = parts[3];

    final fechaProgramada = DateTime.tryParse(fechaStr) ?? DateTime.now();

    // Redireccionar a pantalla de confirmación
    navigatorKey.currentState?.pushNamed(
      '/confirmar',
      arguments: {'loteId': loteId, 'mensaje': mensaje},
    );

    // Actualizar Volteada como confirmada si no existe
    final lotes = await _globalLoteService.loadLotes();
    final index = lotes.indexWhere((l) => l.id == loteId);

    if (index == -1) {
      debugPrint('❌ Lote no encontrado: $loteId');
      return;
    }

    final lote = lotes[index];
    final volteadas = List<Volteada>.from(lote.volteadas ?? []);
    final existe = volteadas.any((v) => v.mensaje == mensaje && v.confirmada);

    if (existe) {
      debugPrint('⚠️ Volteada ya confirmada: "$mensaje"');
      return;
    }

    volteadas.add(
      Volteada(
        id: const Uuid().v4(),
        loteId: loteId,
        mensaje: mensaje,
        temperatura: 0.0,
        humedad: 0.0,
        observacion: '',
        fecha: DateTime.now(),
        fechaProgramada: fechaProgramada,
        confirmada: true,
      ),
    );

    final loteActualizado = lote.copyWith(volteadas: volteadas);
    lotes[index] = loteActualizado;
    await _globalLoteService.saveLotes(lotes);

    debugPrint('✅ Volteada registrada en lote $loteTitle ($loteId)');
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
  }) async {
    final fechaZoned = tz.TZDateTime.from(fechaProgramada, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'scheduled_channel_id',
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

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      fechaZoned,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
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

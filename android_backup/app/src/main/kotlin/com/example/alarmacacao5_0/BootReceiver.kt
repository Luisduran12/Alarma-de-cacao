package com.example.alarmacacao5_0

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("BootReceiver", "📲 Dispositivo reiniciado - iniciando Flutter y reprogramando alarmas")

            // Crear y configurar un FlutterEngine
            val flutterEngine = FlutterEngine(context)

            // Ejecutar el punto de entrada Dart (callbackDispatcher debe estar anotado con @pragma('vm:entry-point'))
            flutterEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    "callbackDispatcher"
                )
            )

            // (Opcional) Guardar el engine si necesitas reutilizarlo
            FlutterEngineCache
                .getInstance()
                .put("boot_engine", flutterEngine)
        }
    }
}

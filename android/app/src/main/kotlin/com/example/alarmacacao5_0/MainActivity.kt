package com.example.alarmacacao5_0

import android.content.Intent
import android.location.LocationManager
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Registra los plugins con el motor Flutter
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        verificarGPS() // ✅ Verifica si el GPS está encendido al iniciar la app
    }

    private fun verificarGPS() {
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val gpsActivo = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)

        if (!gpsActivo) {
            Toast.makeText(this, "🔴 El GPS está desactivado. Activalo manualmente.", Toast.LENGTH_LONG).show()

            // Abre la configuración de ubicación para que el usuario lo active
            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            startActivity(intent)
        }
    }
}

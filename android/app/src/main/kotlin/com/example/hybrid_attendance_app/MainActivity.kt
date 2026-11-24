package com.example.hybrid_attendance_app

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Device identity for attendance: ANDROID_ID is scoped per app-signing key
        // and user on Android 8+, and survives app reinstalls.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hybrid_attendance/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "identity" -> result.success(
                        mapOf(
                            "androidId" to (Settings.Secure.getString(
                                contentResolver, Settings.Secure.ANDROID_ID) ?: ""),
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                        )
                    )
                    else -> result.notImplemented()
                }
            }
    }
}

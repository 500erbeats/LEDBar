package com.example.ledbar

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "led_laufband/dnd"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(nm.isNotificationPolicyAccessGranted)
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "getFilter" -> result.success(nm.currentInterruptionFilter)
                    "setFilter" -> {
                        if (nm.isNotificationPolicyAccessGranted) {
                            nm.setInterruptionFilter(call.arguments as Int)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
package com.dsa.petrol_finder_app

import io.flutter.embedding.android.FlutterActivity


import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import com.oguzhnatly.flutter_android_auto.FAAConstants

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // Use engine from cache if it has been started by Android Auto.
        return FlutterEngineCache.getInstance().get(FAAConstants.flutterEngineId);
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Cache the engine to make it usable by Android Auto.
        FlutterEngineCache.getInstance().put(FAAConstants.flutterEngineId, flutterEngine)
        super.configureFlutterEngine(flutterEngine)
        // Android Auto runs Flutter without a normal Activity.  Handle
        // navigation requests here using the application context so that
        // they work from an Android Auto list-item callback as well as the
        // normal phone UI.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.dsa.petrol_finder_app/android_auto")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startNavigation" -> {
                        val latitude = call.argument<Double>("latitude")
                        val longitude = call.argument<Double>("longitude")
                        if (latitude == null || longitude == null) {
                            result.error("INVALID_COORDINATES", "Latitude and longitude are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val uri = Uri.parse("google.navigation:q=$latitude,$longitude")
                            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            applicationContext.startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("NAVIGATION_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
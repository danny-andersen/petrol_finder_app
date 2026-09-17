package com.dsa.petrol_finder_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.car.app.CarContext
import com.oguzhnatly.flutter_android_auto.AndroidAutoService
import com.oguzhnatly.flutter_android_auto.FAAConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NAVIGATION_CHANNEL = "com.dsa.petrol_finder_app/android_auto"
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // Use the engine from the Android Auto CarAppService when it has
        // already started the app in the background.
        return FlutterEngineCache.getInstance().get(FAAConstants.flutterEngineId)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        FlutterEngineCache.getInstance().put(FAAConstants.flutterEngineId, flutterEngine)
        super.configureFlutterEngine(flutterEngine)
        installAndroidAutoNavigationChannel(flutterEngine)
    }

    /**
     * Navigation is deliberately NOT started from this Activity.
     *
     * flutter_carplay owns the Android Auto CarAppService and exposes its
     * active Session through AndroidAutoService.session.  We use that
     * session's CarContext to hand the destination to the navigation app.
     * This is safe for an Android Auto projected experience and avoids
     * Activity.startActivity(), which is rejected while driving.
     */
    private fun installAndroidAutoNavigationChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NAVIGATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startNavigation" -> {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    val label = call.argument<String>("label") ?: "Destination"

                    if (latitude == null || longitude == null) {
                        result.error(
                            "INVALID_COORDINATES",
                            "Latitude and longitude are required",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    val carContext = AndroidAutoService.session?.carContext
                    if (carContext == null) {
                        result.error(
                            "NO_CAR_CONTEXT",
                            "Android Auto CarContext is not currently available",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        val intent = Intent(CarContext.ACTION_NAVIGATE).apply {
                            data = Uri.parse(
                                "geo:$latitude,$longitude?q=${Uri.encode(label)}"
                            )
                        }

                        // The navigation hand-off is performed by the active
                        // CarContext belonging to the Car App Service.
                        carContext.startCarApp(intent)
                        result.success(null)
                    } catch (t: Throwable) {
                        result.error(
                            "NAVIGATION_FAILED",
                            t.message ?: t.javaClass.simpleName,
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}

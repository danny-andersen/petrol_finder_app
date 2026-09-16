package com.example.android_auto_navigation;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.Result;

public class AndroidAutoNavigationPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "android_auto_navigation/navigation";
    private static final String TAG = "AndroidAutoNavigation";

    private Context applicationContext;
    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if (!"startNavigation".equals(call.method)) {
            result.notImplemented();
            return;
        }

        Number latArg = call.argument("latitude");
        Number lonArg = call.argument("longitude");
        String label = call.argument("label");

        if (latArg == null || lonArg == null) {
            result.error("INVALID_ARGUMENT", "latitude and longitude are required", null);
            return;
        }

        if (applicationContext == null) {
            result.error("NO_CONTEXT", "Android application context is unavailable", null);
            return;
        }

        double latitude = latArg.doubleValue();
        double longitude = lonArg.doubleValue();

        try {
            Uri uri = Uri.parse("google.navigation:q=" + latitude + "," + longitude);
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            Log.i(TAG, "Launching navigation to " + latitude + "," + longitude
                    + (label == null ? "" : " (" + label + ")"));

            applicationContext.startActivity(intent);
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "Unable to launch navigation", e);
            result.error("NAVIGATION_FAILED", e.getMessage(), null);
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        applicationContext = null;
    }
}

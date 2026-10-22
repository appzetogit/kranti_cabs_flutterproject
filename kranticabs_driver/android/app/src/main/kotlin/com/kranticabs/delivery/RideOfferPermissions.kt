package com.kranticabs.delivery

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log

/**
 * The three special permissions the full-screen offer depends on.
 *
 * None of them can be granted by a runtime dialog — each opens its own Settings
 * page, and several OEM builds (Xiaomi, Oppo, Vivo) strip or throw on the direct
 * intents, so every launch is tried in a chain and reports whether *anything*
 * opened. Silently returning success on a failed launch would leave the driver
 * staring at a banner that never clears.
 */
object RideOfferPermissions {

    private const val TAG = "RideOfferPermissions"

    fun canUseFullScreenIntent(context: Context): Boolean {
        // Android 14 denies this to non-call apps by default; before 14 the
        // manifest permission is enough.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        return manager.canUseFullScreenIntent()
    }

    fun canDrawOverlays(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return Settings.canDrawOverlays(context)
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val manager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return manager.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestFullScreenIntent(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false

        return startFirstAvailable(
            activity,
            Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:${activity.packageName}"),
            ),
            appDetailsIntent(activity),
        )
    }

    fun requestOverlay(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false

        return startFirstAvailable(
            activity,
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}"),
            ),
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION),
            appDetailsIntent(activity),
        )
    }

    /**
     * The direct request is the one OEM builds most often reject, hence the
     * three-step chain: ask for this app → the whole battery-optimisation list →
     * this app's settings page.
     */
    fun requestIgnoreBatteryOptimizations(activity: Activity): Boolean = startFirstAvailable(
        activity,
        Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${activity.packageName}"),
        ),
        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        appDetailsIntent(activity),
    )

    private fun appDetailsIntent(activity: Activity) = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:${activity.packageName}"),
    )

    /** Returns true as soon as one intent opens; false if every one failed. */
    private fun startFirstAvailable(activity: Activity, vararg intents: Intent): Boolean {
        for (intent in intents) {
            try {
                activity.startActivity(intent)
                return true
            } catch (error: Exception) {
                Log.w(TAG, "Settings intent ${intent.action} unavailable", error)
            }
        }

        return false
    }
}

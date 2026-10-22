package com.kranticabs.delivery

import android.app.ActivityManager
import android.content.Context
import android.content.SharedPreferences
import io.flutter.plugin.common.MethodChannel

/**
 * Carries the driver's answer from the native card into Dart.
 *
 * The card is answered while the app may be killed, so an action can be
 * produced long before there is a Flutter engine to hand it to. Actions are
 * therefore queued in [SharedPreferences] and drained by Dart on the next run.
 */
object RideOfferBridge {

    const val ACTION_ACCEPT = "accept"
    const val ACTION_REJECT = "reject"

    const val EXTRA_ACTION = "zc_offer_action"

    private const val PREFS = "kranticabs_ride_offer_actions"
    private const val KEY_PENDING = "pending"
    private const val KEY_TOKEN = "driver_token"
    private const val KEY_API_BASE = "api_base_url"
    private const val KEY_LOCALE = "driver_locale"
    private const val RECORD_SEPARATOR = "\n"
    private const val FIELD_SEPARATOR = "|"

    /** Set while a Flutter engine is attached; null whenever it is not. */
    @Volatile
    private var channel: MethodChannel? = null

    /**
     * Whether the app is currently on screen.
     *
     * Driven by the activity's start/stop, not resume/pause: pause also fires
     * when the app is merely covered — the notification shade pulled down, a
     * permission dialog, a system prompt — and treating those as "closed" would
     * throw the full-screen card over an app the driver is actively using.
     *
     * Defaults to false and resets with the process, so a killed app — the case
     * the card exists for — always gets it.
     */
    @Volatile
    var appInForeground: Boolean = false

    /**
     * True when the driver has the app open.
     *
     * Cross-checks the flag above against the process's actual importance, so a
     * missed lifecycle callback (a killed and relaunched process, an activity
     * torn down without onStop) cannot leave the app looking open when it is
     * not, or vice versa.
     */
    fun isAppVisible(context: Context): Boolean {
        if (appInForeground) return true

        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return false
            val processName = context.packageName

            manager.runningAppProcesses?.any { process ->
                process.processName == processName &&
                    process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            } == true
        } catch (_: Exception) {
            // Unknown means "not visible": showing the card to a driver who is
            // already in the app is a smaller failure than never showing it.
            false
        }
    }

    fun attach(methodChannel: MethodChannel?) {
        channel = methodChannel
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Records one answer.
     *
     * The queue is the only delivery path — a live [MethodChannel] is used to
     * *nudge* Dart into draining it, never to hand the answer over directly.
     * Delivering both ways would double-fire every accept made while the app
     * happened to be alive, since nothing clears the queue but a drain.
     */
    fun record(context: Context, action: String, rideId: String) {
        if (rideId.isEmpty()) return

        val existing = prefs(context).getString(KEY_PENDING, "").orEmpty()
        val record = "$action$FIELD_SEPARATOR$rideId"
        val next = if (existing.isEmpty()) record else "$existing$RECORD_SEPARATOR$record"
        prefs(context).edit().putString(KEY_PENDING, next).apply()

        notifyPending()
    }

    /** Asks Dart to drain the queue now, if there is an engine to ask. */
    fun notifyPending() {
        channel?.invokeMethod("onRideOfferActionsPending", null)
    }

    /**
     * Caches the signed-in driver's session so the offer card can answer the
     * server without a Flutter engine.
     *
     * Written by Dart on login and cleared on logout. Only used to decline an
     * offer — the one action that must reach the server while the app stays
     * closed.
     */
    fun saveSession(context: Context, token: String, apiBaseUrl: String) {
        prefs(context).edit()
            .putString(KEY_TOKEN, token)
            .putString(KEY_API_BASE, apiBaseUrl)
            .apply()
    }

    fun clearSession(context: Context) {
        prefs(context).edit().remove(KEY_TOKEN).remove(KEY_API_BASE).apply()
    }

    /**
     * The driver's selected app language code (en/hi/kn/ta/te), mirrored from
     * Dart so the native ride-offer voice can speak in the right language while
     * the Flutter engine is dead.
     */
    fun saveLocale(context: Context, code: String) {
        prefs(context).edit().putString(KEY_LOCALE, code).apply()
    }

    fun driverLocale(context: Context): String =
        prefs(context).getString(KEY_LOCALE, "en").orEmpty().ifEmpty { "en" }

    fun sessionToken(context: Context): String = prefs(context).getString(KEY_TOKEN, "").orEmpty()

    fun apiBaseUrl(context: Context): String = prefs(context).getString(KEY_API_BASE, "").orEmpty()

    /** Returns every queued answer and clears the queue. */
    fun consumePending(context: Context): List<Map<String, String>> {
        val stored = prefs(context).getString(KEY_PENDING, "").orEmpty()
        if (stored.isEmpty()) return emptyList()

        prefs(context).edit().remove(KEY_PENDING).apply()

        return stored.split(RECORD_SEPARATOR)
            .mapNotNull { record ->
                val parts = record.split(FIELD_SEPARATOR, limit = 2)
                if (parts.size != 2 || parts[1].isEmpty()) return@mapNotNull null
                mapOf("action" to parts[0], "rideId" to parts[1])
            }
    }
}

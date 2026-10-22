package com.kranticabs.delivery

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.kranticabs.delivery/app_launcher"

    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wakeScreenAndUnlock()
    }

    /// The card starts this activity after an Accept. The answer itself is
    /// already queued by then, so all this has to do is prompt a drain.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        RideOfferBridge.notifyPending()
    }

    /// Start/stop rather than resume/pause: the app is still open behind a
    /// pulled-down notification shade or a permission dialog, and those only
    /// pause it. Treating them as "closed" would let a ride offer throw the
    /// full-screen card over an app the driver is actively using.
    override fun onStart() {
        super.onStart()
        RideOfferBridge.appInForeground = true
    }

    override fun onStop() {
        RideOfferBridge.appInForeground = false
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        // With the app open, the in-app offer screen and its own ringtone take
        // over; leaving the native alert running would double it.
        RideOfferSoundPlayer.stop()
        RideOfferVoice.stop()
        // Covers the return from a Settings page and from the offer card alike.
        RideOfferBridge.notifyPending()
    }

    override fun onDestroy() {
        RideOfferBridge.appInForeground = false
        RideOfferBridge.attach(null)
        channel = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        RideOfferBridge.attach(methodChannel)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToForeground" -> {
                    bringToForeground()
                    result.success(true)
                }
                "wakeScreen" -> {
                    wakeScreenAndUnlock()
                    result.success(true)
                }

                // Answers queued while no Flutter engine was alive — the normal
                // case, since the card is answered with the app killed.
                "consumePendingRideOfferActions" -> {
                    result.success(RideOfferBridge.consumePending(applicationContext))
                }

                // Lets the offer card decline against the server while the app
                // is closed — see RideOfferRejectSender.
                "setDriverSession" -> {
                    RideOfferBridge.saveSession(
                        applicationContext,
                        call.argument<String>("token").orEmpty(),
                        call.argument<String>("apiBaseUrl").orEmpty(),
                    )
                    result.success(true)
                }

                "clearDriverSession" -> {
                    RideOfferBridge.clearSession(applicationContext)
                    result.success(true)
                }

                // Mirrors the driver's chosen language so the native background
                // ride-offer voice speaks in it with the app killed.
                "setDriverLocale" -> {
                    RideOfferBridge.saveLocale(
                        applicationContext,
                        call.argument<String>("code").orEmpty(),
                    )
                    result.success(true)
                }

                "dismissRideOffer" -> {
                    RideOfferNotifier.cancelOffer(
                        applicationContext,
                        call.argument<String>("rideId").orEmpty(),
                    )
                    result.success(true)
                }

                "getRideOfferPermissions" -> {
                    result.success(
                        mapOf(
                            "fullScreenIntent" to RideOfferPermissions.canUseFullScreenIntent(this),
                            "overlay" to RideOfferPermissions.canDrawOverlays(this),
                            "batteryOptimizations" to
                                RideOfferPermissions.isIgnoringBatteryOptimizations(this),
                        ),
                    )
                }

                // Each returns whether a Settings page actually opened, so Dart
                // knows whether waiting for a resume is meaningful.
                "requestFullScreenIntentPermission" ->
                    result.success(RideOfferPermissions.requestFullScreenIntent(this))

                "requestOverlayPermission" ->
                    result.success(RideOfferPermissions.requestOverlay(this))

                "requestIgnoreBatteryOptimizations" ->
                    result.success(RideOfferPermissions.requestIgnoreBatteryOptimizations(this))

                else -> result.notImplemented()
            }
        }

        // A cold start from the card gets its drain as soon as Dart registers a
        // handler; this covers a warm engine that was already attached.
        RideOfferBridge.notifyPending()
    }

    private fun wakeScreenAndUnlock() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun bringToForeground() {
        wakeScreenAndUnlock()
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        startActivity(intent)
    }
}

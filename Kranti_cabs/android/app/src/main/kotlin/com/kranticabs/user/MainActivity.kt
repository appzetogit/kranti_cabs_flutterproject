package com.kranticabs.user

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands a location the rider tapped in another app (a WhatsApp pin, a pasted
 * Google Maps link, a shared text) to Flutter, which turns it into a drop point.
 *
 * Done natively instead of through Flutter's own deep linking on purpose: that
 * would feed the https/geo URL to go_router as if it were an in-app route, and
 * it cannot see ACTION_SEND text at all.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            if (call.method == "getInitialShare") {
                result.success(pendingShare)
                pendingShare = null
            } else {
                result.notImplemented()
            }
        }
        channel = methodChannel

        pendingShare = extractShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val payload = extractShare(intent) ?: return
        val active = channel
        if (active != null) {
            active.invokeMethod("onShare", payload)
        } else {
            pendingShare = payload
        }
    }

    private fun extractShare(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            else -> null
        }
    }

    companion object {
        private const val CHANNEL = "zicab/shared_location"
    }
}

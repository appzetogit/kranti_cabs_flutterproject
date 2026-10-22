package com.kranticabs.delivery

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Drives the background/overlay ride-offer alert **vibration**.
 *
 * By product decision the background offer no longer plays a ring tone — the
 * order is instead READ ALOUD by [RideOfferVoice] (in the driver's language),
 * accompanied by a strong vibration. This object therefore only owns the
 * vibration now; the notification channel stays muted so nothing else sounds.
 *
 * Kept as `RideOfferSoundPlayer` with the same start/stop API so the existing
 * call sites (notifier, overlay activity, MainActivity) are unchanged.
 */
object RideOfferSoundPlayer {

    private const val TAG = "RideOfferSound"

    /// Hard ceiling so a lost stop() can never leave a phone buzzing forever.
    private const val MAX_RING_MS = 120_000L

    private val lock = Any()

    private var vibrator: Vibrator? = null

    /// Which offer is currently alerting, so repeat dispatch waves for the same
    /// ride are ignored rather than restarting the vibration from the top.
    private var ringingRideId: String? = null

    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var stopRunnable: Runnable? = null

    fun start(context: Context, rideId: String, maxDurationMs: Long) {
        if (rideId.isEmpty()) return

        synchronized(lock) {
            // Same offer already buzzing — do not restart on a re-offer wave.
            if (ringingRideId == rideId && vibrator != null) return

            stopLocked()

            startVibration(context)
            ringingRideId = rideId

            // Hard stop at the offer's own expiry so a missed stop() cannot leave
            // the phone vibrating in the driver's pocket.
            Runnable { stopFor(rideId) }.also { runnable ->
                stopRunnable = runnable
                handler.postDelayed(runnable, maxDurationMs.coerceIn(1_000L, MAX_RING_MS))
            }
        }
    }

    /** Stops immediately. Safe to call when nothing is alerting. */
    fun stop() {
        synchronized(lock) { stopLocked() }
    }

    /**
     * Stops only if [rideId] is the offer currently alerting, so a
     * `ride_request_closed` for an older ride cannot silence the one the driver
     * is looking at right now.
     */
    fun stopFor(rideId: String) {
        synchronized(lock) {
            if (ringingRideId == rideId) stopLocked()
        }
    }

    private fun stopLocked() {
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = null

        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
        ringingRideId = null
    }

    private fun startVibration(context: Context) {
        try {
            val service = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            } ?: return

            // Strong, insistent pattern: long buzz / short gap, repeating.
            val timings = longArrayOf(0, 900, 350, 900, 350)
            // Max amplitude (255) on every buzz segment for a high-intensity feel.
            val amplitudes = intArrayOf(0, 255, 0, 255, 0)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = if (context.hasAmplitudeControl()) {
                    VibrationEffect.createWaveform(timings, amplitudes, 0)
                } else {
                    VibrationEffect.createWaveform(timings, 0)
                }
                service.vibrate(
                    effect,
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                service.vibrate(timings, 0)
            }

            vibrator = service
        } catch (error: Exception) {
            Log.w(TAG, "Could not start ride-offer vibration", error)
        }
    }

    private fun Context.hasAmplitudeControl(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                    ?.defaultVibrator?.hasAmplitudeControl() == true
            } else {
                @Suppress("DEPRECATION")
                (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.hasAmplitudeControl() == true
            }
        } catch (_: Exception) {
            false
        }
    }
}

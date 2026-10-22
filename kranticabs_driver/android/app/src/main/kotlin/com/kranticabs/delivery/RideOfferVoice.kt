package com.kranticabs.delivery

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

/**
 * Announces a new ride offer aloud — amount, pickup and drop — in the driver's
 * selected language, for the BACKGROUND / app-killed case where the full-screen
 * card is shown natively and the Flutter engine (and its flutter_tts voice) is
 * not alive.
 *
 * This REPLACES the ride tone in the background: the driver hears the order read
 * out instead of a ring. It keeps re-announcing on a short loop until the offer
 * is answered or expires, so a driver who missed the first read still hears it.
 * The templates mirror the Flutter `voice.new_order` strings.
 */
object RideOfferVoice {

    private const val TAG = "RideOfferVoice"
    private const val MAX_MS = 120_000L
    private const val REPEAT_GAP_MS = 2_500L

    private val lock = Any()
    private var tts: TextToSpeech? = null
    private var speakingRideId: String? = null
    private var ready = false
    private var pendingText: String? = null

    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null
    private var repeatRunnable: Runnable? = null

    private val locales = mapOf(
        "en" to Locale("en", "IN"),
        "hi" to Locale("hi", "IN"),
        "kn" to Locale("kn", "IN"),
        "ta" to Locale("ta", "IN"),
        "te" to Locale("te", "IN"),
    )

    private val templates = mapOf(
        "en" to "New order. Fare %1\$s rupees. Pickup at %2\$s. Drop at %3\$s.",
        "hi" to "नया ऑर्डर। किराया %1\$s रुपये। पिकअप %2\$s। ड्रॉप %3\$s।",
        "kn" to "ಹೊಸ ಆರ್ಡರ್. ದರ %1\$s ರೂಪಾಯಿ. ಪಿಕಪ್ %2\$s. ಡ್ರಾಪ್ %3\$s.",
        "ta" to "புதிய ஆர்டர். கட்டணம் %1\$s ரூபாய். பிக்அப் %2\$s. டிராப் %3\$s.",
        "te" to "కొత్త ఆర్డర్. ఛార్జీ %1\$s రూపాయలు. పికప్ %2\$s. డ్రాప్ %3\$s.",
    )

    fun start(context: Context, payload: RideOfferPayload, localeCode: String, maxDurationMs: Long) {
        if (payload.rideId.isEmpty()) return
        val code = if (templates.containsKey(localeCode)) localeCode else "en"
        val template = templates[code] ?: templates["en"]!!
        val text = String.format(
            template,
            payload.fare.ifEmpty { "0" },
            payload.pickupAddress.ifEmpty { "-" },
            payload.dropAddress.ifEmpty { "-" },
        )
        val locale = locales[code] ?: Locale("en", "IN")

        synchronized(lock) {
            // Repeat dispatch waves for the same ride must not restart the voice.
            if (speakingRideId == payload.rideId && tts != null) return
            stopLocked()

            speakingRideId = payload.rideId
            pendingText = text

            try {
                tts = TextToSpeech(context.applicationContext) { status ->
                    if (status != TextToSpeech.SUCCESS) {
                        Log.w(TAG, "TTS init failed status=$status")
                        return@TextToSpeech
                    }
                    try {
                        val res = tts?.setLanguage(locale)
                        if (res == TextToSpeech.LANG_MISSING_DATA || res == TextToSpeech.LANG_NOT_SUPPORTED) {
                            // Fall back so the order is still read out (in whatever
                            // default voice the device has) rather than staying silent.
                            tts?.setLanguage(Locale("en", "IN"))
                        }
                        tts?.setSpeechRate(0.95f)
                    } catch (_: Exception) {
                    }
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) = scheduleRepeat()
                        @Deprecated("deprecated in API 21")
                        override fun onError(utteranceId: String?) {}
                        override fun onError(utteranceId: String?, errorCode: Int) {}
                    })
                    ready = true
                    speakNow()
                }
            } catch (error: Exception) {
                Log.w(TAG, "Could not start ride-offer voice", error)
                stopLocked()
                return
            }

            Runnable { stopFor(payload.rideId) }.also {
                stopRunnable = it
                handler.postDelayed(it, maxDurationMs.coerceIn(1_000L, MAX_MS))
            }
        }
    }

    private fun speakNow() {
        val text = pendingText ?: return
        try {
            // Loud + on the notification stream so the order is clearly heard
            // even if the device's media volume is low.
            val params = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_NOTIFICATION)
            }
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, speakingRideId ?: "offer")
        } catch (error: Exception) {
            Log.w(TAG, "TTS speak failed", error)
        }
    }

    private fun scheduleRepeat() {
        synchronized(lock) {
            if (speakingRideId == null) return
            repeatRunnable?.let { handler.removeCallbacks(it) }
            Runnable {
                synchronized(lock) { if (speakingRideId != null && ready) speakNow() }
            }.also {
                repeatRunnable = it
                handler.postDelayed(it, REPEAT_GAP_MS)
            }
        }
    }

    fun stop() {
        synchronized(lock) { stopLocked() }
    }

    fun stopFor(rideId: String) {
        synchronized(lock) { if (speakingRideId == rideId) stopLocked() }
    }

    private fun stopLocked() {
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = null
        repeatRunnable?.let { handler.removeCallbacks(it) }
        repeatRunnable = null
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        speakingRideId = null
        ready = false
        pendingText = null
    }
}

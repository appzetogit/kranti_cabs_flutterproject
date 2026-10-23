package com.kranticabs.delivery

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.lang.ref.WeakReference

/**
 * The full-screen ride offer, drawn over the home screen or lock screen.
 *
 * Deliberately a plain [Activity] rather than a FlutterActivity: it is launched
 * from a push while the app may be killed and the screen off, and starting a
 * Flutter engine on that path is both slow and unreliable. Everything it shows
 * comes from the intent extras.
 */
class RideOfferActivity : Activity() {

    private var payload: RideOfferPayload? = null
    private var countdown: CountDownTimer? = null
    private var answered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        showOverLockScreen()
        setContentView(R.layout.activity_ride_offer)
        // Ignore Accept/Reject taps made through another app's overlay window
        // (tapjacking, overlay-based auto clickers).
        window.decorView.filterTouchesWhenObscured = true

        val offer = RideOfferPayload.fromExtras(intent?.extras)
        if (offer == null) {
            finish()
            return
        }

        bind(offer)
    }

    /**
     * A `singleTask` activity that is already up receives the next offer here
     * rather than through [onCreate].
     */
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)

        val offer = RideOfferPayload.fromExtras(intent?.extras) ?: return
        answered = false
        bind(offer)
    }

    override fun onDestroy() {
        countdown?.cancel()
        countdown = null
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    /** Back must not silently drop an offer that is still live. */
    override fun onBackPressed() {
        // Intentionally ignored — the driver answers with Accept or Decline, or
        // the countdown expires.
    }

    private fun bind(offer: RideOfferPayload) {
        payload = offer
        current = WeakReference(this)

        findViewById<TextView>(R.id.offer_fare).text = formatFare(offer.fare)
        // Whatever the admin named this vehicle type, straight from the payload.
        findViewById<TextView>(R.id.offer_vehicle_label).text =
            offer.vehicleLabel.ifEmpty { offer.vehicleIconType.ifEmpty { "Ride" } }
        findViewById<TextView>(R.id.offer_per_km).apply {
            val fare = offer.fare.toDoubleOrNull()
            val km = offer.tripDistanceKm.toDoubleOrNull()
            if (fare != null && km != null && km > 0) {
                text = "· ₹${String.format(java.util.Locale.US, "%.1f", fare / km)}/km"
                visibility = android.view.View.VISIBLE
            } else {
                visibility = android.view.View.GONE
            }
        }
        findViewById<TextView>(R.id.offer_pickup_distance).text = formatKm(offer.pickupDistanceKm)
        findViewById<TextView>(R.id.offer_trip_distance).text = formatKm(offer.tripDistanceKm)
        findViewById<TextView>(R.id.offer_pickup_address).text = styleAddress(offer.pickupAddress)
        findViewById<TextView>(R.id.offer_drop_address).text = styleAddress(offer.dropAddress)

        bindVehicleArt(offer)

        findViewById<Button>(R.id.offer_accept).setOnClickListener { answer(RideOfferBridge.ACTION_ACCEPT) }
        findViewById<Button>(R.id.offer_decline).setOnClickListener { answer(RideOfferBridge.ACTION_REJECT) }

        startCountdown(offer.expiresInSeconds)
    }

    /**
     * Reads the vehicle art straight out of the APK's Flutter assets, so the
     * card and the map markers stay on one image set instead of drifting apart
     * as two copies.
     */
    private fun bindVehicleArt(offer: RideOfferPayload) {
        val view = findViewById<ImageView>(R.id.offer_vehicle_art)
        val assetName = when (vehicleFamily(offer)) {
            "bike" -> "markerbike.png"
            "auto" -> "markerauto.webp"
            else -> "markersedan.webp"
        }

        try {
            assets.open("flutter_assets/assets/$assetName").use { stream ->
                view.setImageBitmap(BitmapFactory.decodeStream(stream))
            }
        } catch (error: Exception) {
            // Missing art must never cost the driver the offer itself.
            Log.w(TAG, "Vehicle art $assetName unavailable", error)
            view.setImageResource(R.mipmap.ic_launcher)
        }
    }

    private fun vehicleFamily(offer: RideOfferPayload): String {
        val raw = "${offer.vehicleIconType} ${offer.vehicleLabel}".lowercase()
        return when {
            raw.contains("bike") || raw.contains("moto") || raw.contains("scooter") ||
                raw.contains("2wheeler") || raw.contains("two_wheeler") || raw.contains("parcel") -> "bike"
            raw.contains("auto") || raw.contains("rickshaw") || raw.contains("tuk") ||
                raw.contains("3wheeler") -> "auto"
            else -> "car"
        }
    }

    private fun startCountdown(seconds: Int) {
        countdown?.cancel()
        val accept = findViewById<Button>(R.id.offer_accept)

        countdown = object : CountDownTimer(seconds * 1000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                val remaining = (millisUntilFinished / 1000L).toInt()
                accept.text = getString(R.string.zc_offer_accept_countdown, remaining)
            }

            override fun onFinish() {
                accept.text = getString(R.string.zc_offer_accept)
                // Expiry is not a decline: the server has already moved this
                // offer on, and recording a reject here would mark the driver as
                // having refused a ride they were never shown in time.
                dismiss()
            }
        }.start()
    }

    private fun answer(offerAction: String) {
        if (answered) return
        answered = true
        countdown?.cancel()

        val rideId = payload?.rideId.orEmpty()
        RideOfferBridge.record(applicationContext, offerAction, rideId)

        // Answered against the server straight from the tap, before the app is
        // even asked to start. Waiting for the app to open cost enough time on a
        // cold start that the offer had already moved on.
        if (offerAction == RideOfferBridge.ACTION_ACCEPT) {
            RideOfferAnswerSender.accept(applicationContext, rideId)
        } else {
            RideOfferAnswerSender.reject(applicationContext, rideId)
        }

        if (offerAction == RideOfferBridge.ACTION_ACCEPT) {
            // The ride is already claimed by now; opening the app is navigation
            // to the trip, not the accept itself.
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    putExtra(RideOfferBridge.EXTRA_ACTION, RideOfferBridge.ACTION_ACCEPT)
                    putExtra(RideOfferPayload.EXTRA_RIDE_ID, rideId)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                },
            )
        }

        dismiss()
    }

    private fun dismiss() {
        countdown?.cancel()
        payload?.rideId?.let { rideId ->
            // Silence before anything else — the driver has answered and the
            // alert (vibration + voice) must not outlive the card by a moment.
            RideOfferSoundPlayer.stopFor(rideId)
            RideOfferVoice.stopFor(rideId)
            NotificationManagerCompat.from(this).cancel(RideOfferNotifier.notificationId(rideId))
        }
        finish()
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            (getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)
                ?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun formatFare(fare: String): String {
        val amount = fare.toDoubleOrNull() ?: return if (fare.isEmpty()) "" else "₹$fare"
        return "₹${Math.round(amount)}"
    }

    private fun formatKm(km: String): String = if (km.isEmpty()) "—" else "$km Km"

    /**
     * Emphasises the locality and greys the rest of the address.
     *
     * Addresses arrive as "Palasia Square, New Palasia, Indore" — the first
     * segment is the bit a driver actually navigates by, so it is set in the
     * ink colour and the trailing detail is left quiet behind it.
     */
    private fun styleAddress(address: String): CharSequence {
        val trimmed = address.trim()
        if (trimmed.isEmpty()) return ""

        val separator = trimmed.indexOf(',')
        if (separator <= 0) return trimmed

        val locality = trimmed.substring(0, separator)
        val remainder = trimmed.substring(separator + 1).trim()
        if (remainder.isEmpty()) return locality

        val spannable = SpannableStringBuilder()
        spannable.append(locality)
        spannable.setSpan(
            StyleSpan(Typeface.BOLD),
            0,
            locality.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
        )
        spannable.setSpan(
            ForegroundColorSpan(ContextCompat.getColor(this, R.color.zc_offer_ink)),
            0,
            locality.length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
        )
        spannable.append(" - ")
        spannable.append(remainder)

        return spannable
    }

    companion object {
        private const val TAG = "RideOfferActivity"

        /**
         * The live card, if any. Held weakly so a finished activity cannot be
         * kept alive by this reference.
         */
        private var current: WeakReference<RideOfferActivity>? = null

        /** Closes the card for [rideId] when the server withdraws the offer. */
        fun dismissFor(rideId: String) {
            val activity = current?.get() ?: return
            if (activity.payload?.rideId != rideId) return
            activity.runOnUiThread { activity.dismiss() }
        }
    }
}

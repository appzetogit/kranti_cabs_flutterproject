package com.kranticabs.delivery

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Posts the full-screen ride-offer alert.
 *
 * Runs from [RideRequestMessagingService], which means it must work with no
 * Flutter engine, no activity, and the screen off.
 */
object RideOfferNotifier {

    private const val TAG = "RideOfferNotifier"

    /**
     * A channel's importance and sound are frozen at creation — later changes to
     * either are ignored for every install that already has it. Bump this id
     * (…_v4, _v5) whenever importance or sound changes, or the old values live
     * on forever.
     *
     * v3 mutes the channel: the tone is played on a loop by
     * [RideOfferSoundPlayer] instead, and leaving the channel sound on would
     * fire a second, one-shot copy over the top of it.
     */
    private const val CHANNEL_ID = "ride_offer_v3"

    private const val WAKE_LOCK_TAG = "kranticabs:ride-offer"
    private const val WAKE_LOCK_TIMEOUT_MS = 10_000L

    fun notificationId(rideId: String): Int = rideId.hashCode()

    fun postOffer(context: Context, payload: RideOfferPayload) {
        ensureChannel(context)

        // Starts here rather than in the activity so the driver hears the offer
        // even on a device where the full-screen intent is downgraded to a
        // heads-up and no activity comes up. Repeat waves for the same ride are
        // ignored inside the player, so the tone is not restarted.
        RideOfferSoundPlayer.start(
            context,
            payload.rideId,
            payload.expiresInSeconds * 1000L,
        )

        // Background alert is voice-only (no ring): read the order aloud in the
        // driver's language, alongside the strong vibration above.
        RideOfferVoice.start(
            context,
            payload,
            RideOfferBridge.driverLocale(context),
            payload.expiresInSeconds * 1000L,
        )

        // A full-screen intent only goes straight to the activity while the
        // screen is off or locked; on an awake device it degrades to a heads-up.
        // Waking first is what makes the card appear rather than a banner.
        wakeScreen(context)

        val fullScreenIntent = PendingIntent.getActivity(
            context,
            notificationId(payload.rideId),
            offerIntent(context, payload),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(context.getString(R.string.zc_offer_title))
            .setContentText(payload.pickupAddress.ifEmpty { context.getString(R.string.zc_offer_body) })
            .setPriority(NotificationCompat.PRIORITY_MAX)
            // Call category earns call-style treatment and clears most DND rules.
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(true)
            .setTimeoutAfter(payload.expiresInSeconds * 1000L)
            .setContentIntent(fullScreenIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .setDefaults(Notification.DEFAULT_VIBRATE)
            .build()

        try {
            NotificationManagerCompat.from(context)
                .notify(notificationId(payload.rideId), notification)
        } catch (error: SecurityException) {
            // POST_NOTIFICATIONS refused. The overlay path below can still work.
            Log.w(TAG, "Ride-offer notification refused", error)
        }

        startOverlayFallback(context, payload)
    }

    fun cancelOffer(context: Context, rideId: String) {
        if (rideId.isEmpty()) return
        // Scoped to this ride so a late withdrawal for an earlier offer cannot
        // silence the one the driver is currently being shown.
        RideOfferSoundPlayer.stopFor(rideId)
        RideOfferVoice.stopFor(rideId)
        NotificationManagerCompat.from(context).cancel(notificationId(rideId))
        RideOfferActivity.dismissFor(rideId)
    }

    private fun offerIntent(context: Context, payload: RideOfferPayload): Intent =
        payload.writeTo(Intent(context, RideOfferActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NO_USER_ACTION
        }

    /**
     * Launches the card directly, in addition to the notification.
     *
     * Holding SYSTEM_ALERT_WINDOW lifts Android 10+'s background-activity-launch
     * ban, and this is what makes the alert reliable on Android 14, where
     * USE_FULL_SCREEN_INTENT is denied to non-call apps by default and the
     * notification alone would only produce a heads-up.
     */
    private fun startOverlayFallback(context: Context, payload: RideOfferPayload) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) return

        try {
            context.startActivity(offerIntent(context, payload))
        } catch (error: Exception) {
            Log.w(TAG, "Overlay launch of ride-offer card failed", error)
        }
    }

    private fun wakeScreen(context: Context) {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return

        try {
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                WAKE_LOCK_TAG,
            )
            // Held for the timeout rather than released immediately: the screen
            // has to stay on long enough for the activity to come up and take
            // over with its own turnScreenOn, or it darkens again mid-launch.
            wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)
        } catch (error: Exception) {
            Log.w(TAG, "Could not wake the screen for a ride offer", error)
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.zc_offer_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.zc_offer_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
            // Sound and vibration are driven by RideOfferSoundPlayer so they can
            // run for as long as the offer stands. A channel can only fire them
            // once per post, which is the whole problem this replaces.
            setSound(null, null)
            enableVibration(false)
        }

        manager.createNotificationChannel(channel)
    }
}

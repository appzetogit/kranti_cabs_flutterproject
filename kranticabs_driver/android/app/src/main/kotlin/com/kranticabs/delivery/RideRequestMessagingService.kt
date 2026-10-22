package com.kranticabs.delivery

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Posts the native ride-offer card the moment a ride-request push lands.
 *
 * Extends [FlutterFirebaseMessagingService], not `FirebaseMessagingService`:
 * only one messaging service in a manifest wins, and this one is registered at
 * a higher intent-filter priority than the plugin's, so a plain subclass would
 * silence `firebase_messaging` and break every other push in the app.
 * [onMessageReceived] always calls `super`, which is what keeps that true if the
 * plugin ever moves work back into the service. (As of 15.2.10 it delivers to
 * Dart from its own broadcast receiver instead, so `super` is currently a
 * no-op — do not take that as licence to drop it.)
 *
 * The offers themselves arrive as data-only pushes. A message carrying a
 * `notification` block is routed by FCM straight to the system tray while the
 * app is backgrounded and never reaches this class at all.
 */
class RideRequestMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        // Dart first: whatever happens below must not cost the plugin a message.
        super.onMessageReceived(message)

        try {
            handleRideOffer(message)
        } catch (error: Exception) {
            Log.e(TAG, "Failed to handle ride-offer push", error)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
    }

    private fun handleRideOffer(message: RemoteMessage) {
        val data = message.data
        when (data["type"]) {
            TYPE_RIDE_REQUEST -> {
                // The card exists for a driver who is *not* in the app. With the
                // app open they already get the in-app offer screen and its
                // ringtone, and covering that with a full-screen card would
                // double both the alert and the sound.
                if (RideOfferBridge.isAppVisible(applicationContext)) return

                val payload = RideOfferPayload.fromData(data) ?: return
                RideOfferNotifier.postOffer(applicationContext, payload)
            }

            TYPE_RIDE_REQUEST_CLOSED -> {
                RideOfferNotifier.cancelOffer(applicationContext, data["rideId"].orEmpty())
            }
        }
    }

    private companion object {
        const val TAG = "RideRequestMessaging"
        const val TYPE_RIDE_REQUEST = "ride_request"
        const val TYPE_RIDE_REQUEST_CLOSED = "ride_request_closed"
    }
}

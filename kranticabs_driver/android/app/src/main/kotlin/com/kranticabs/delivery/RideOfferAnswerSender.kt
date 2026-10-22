package com.kranticabs.delivery

import android.content.Context
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Sends the driver's answer to the server the moment the card is tapped.
 *
 * Both answers have to work with the app closed, where there is no socket to
 * emit on and no Dart engine to do it for us.
 *
 * Accept in particular used to travel a long way before reaching the server —
 * queue the action, launch the app, boot the Flutter engine, wait for the
 * socket, re-check the offer, emit. On a cold start that ran to many seconds,
 * by which point dispatch had moved the ride on and the driver arrived in the
 * app on "Ride is no longer available for acceptance" having done nothing
 * wrong. Claiming the ride straight from the tap removes all of that from the
 * critical path; opening the app becomes navigation, not the accept itself.
 *
 * Best-effort: the answer is still queued locally, so a failure here falls back
 * to the old path rather than losing the driver's decision.
 */
object RideOfferAnswerSender {

    private const val TAG = "RideOfferAnswer"
    private const val TIMEOUT_MS = 10_000

    private val executor = Executors.newSingleThreadExecutor()

    fun accept(context: Context, rideId: String) = send(context, rideId, "accept")

    fun reject(context: Context, rideId: String) = send(context, rideId, "reject")

    private fun send(context: Context, rideId: String, action: String) {
        if (rideId.isEmpty()) return

        val token = RideOfferBridge.sessionToken(context)
        val baseUrl = RideOfferBridge.apiBaseUrl(context).trimEnd('/')

        if (token.isEmpty() || baseUrl.isEmpty()) {
            // Not signed in as far as native can tell — the queued action gets
            // flushed by Dart on the next run.
            Log.w(TAG, "No cached session; $action for $rideId falls back to the queue")
            return
        }

        executor.execute {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL("$baseUrl/drivers/ride-offers/$rideId/$action").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = TIMEOUT_MS
                    readTimeout = TIMEOUT_MS
                    doOutput = true
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "application/json")
                }

                connection.outputStream.use { it.write("{}".toByteArray()) }

                val status = connection.responseCode
                if (status in 200..299) {
                    Log.i(TAG, "$action for $rideId accepted by server")
                } else {
                    Log.w(TAG, "$action for $rideId rejected by server: HTTP $status")
                }
            } catch (error: Exception) {
                Log.w(TAG, "Could not send $action for $rideId", error)
            } finally {
                connection?.disconnect()
            }
        }
    }
}

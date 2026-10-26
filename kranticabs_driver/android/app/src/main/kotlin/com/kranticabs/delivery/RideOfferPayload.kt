package com.kranticabs.delivery

import android.content.Intent
import android.os.Bundle

/**
 * Everything the offer card renders, carried in the push's `data` map.
 *
 * The card has to be drawable with the app killed and no network, so nothing
 * here may be fetched — whatever is not in `data` cannot be shown.
 */
data class RideOfferPayload(
    val rideId: String,
    val fare: String,
    val pickupAddress: String,
    val dropAddress: String,
    val pickupDistanceKm: String,
    val tripDistanceKm: String,
    val vehicleIconType: String,
    val vehicleLabel: String,
    val expiresInSeconds: Int,
    val riderName: String,
    /** `intercity` (outstation), `hourly_rental`, `parcel`... straight from the push. */
    val serviceType: String = "",
) {
    fun writeTo(intent: Intent): Intent = intent.apply {
        putExtra(EXTRA_RIDE_ID, rideId)
        putExtra(EXTRA_FARE, fare)
        putExtra(EXTRA_PICKUP_ADDRESS, pickupAddress)
        putExtra(EXTRA_DROP_ADDRESS, dropAddress)
        putExtra(EXTRA_PICKUP_DISTANCE, pickupDistanceKm)
        putExtra(EXTRA_TRIP_DISTANCE, tripDistanceKm)
        putExtra(EXTRA_VEHICLE_ICON_TYPE, vehicleIconType)
        putExtra(EXTRA_VEHICLE_LABEL, vehicleLabel)
        putExtra(EXTRA_EXPIRES_IN, expiresInSeconds)
        putExtra(EXTRA_RIDER_NAME, riderName)
        putExtra(EXTRA_SERVICE_TYPE, serviceType)
    }

    companion object {
        const val EXTRA_RIDE_ID = "zc_ride_id"
        private const val EXTRA_FARE = "zc_fare"
        private const val EXTRA_PICKUP_ADDRESS = "zc_pickup_address"
        private const val EXTRA_DROP_ADDRESS = "zc_drop_address"
        private const val EXTRA_PICKUP_DISTANCE = "zc_pickup_distance"
        private const val EXTRA_TRIP_DISTANCE = "zc_trip_distance"
        private const val EXTRA_VEHICLE_ICON_TYPE = "zc_vehicle_icon_type"
        private const val EXTRA_VEHICLE_LABEL = "zc_vehicle_label"
        private const val EXTRA_EXPIRES_IN = "zc_expires_in"
        private const val EXTRA_RIDER_NAME = "zc_rider_name"
        private const val EXTRA_SERVICE_TYPE = "zc_service_type"

        private const val DEFAULT_EXPIRY_SECONDS = 25

        /** Returns null when the message is not a usable ride offer. */
        fun fromData(data: Map<String, String>): RideOfferPayload? {
            val rideId = data["rideId"].orEmpty().trim()
            if (rideId.isEmpty()) return null

            return RideOfferPayload(
                rideId = rideId,
                fare = data["fare"].orEmpty().trim(),
                pickupAddress = data["pickupAddress"].orEmpty().trim(),
                dropAddress = data["dropAddress"].orEmpty().trim(),
                pickupDistanceKm = data["pickupDistanceKm"].orEmpty().trim(),
                tripDistanceKm = data["tripDistanceKm"].orEmpty().trim(),
                vehicleIconType = data["vehicleIconType"].orEmpty().trim(),
                vehicleLabel = data["vehicleLabel"].orEmpty().trim(),
                // A zero or unparseable window would dismiss the card instantly.
                expiresInSeconds = data["expiresInSeconds"]?.trim()?.toIntOrNull()
                    ?.takeIf { it > 0 } ?: DEFAULT_EXPIRY_SECONDS,
                riderName = data["riderName"].orEmpty().trim(),
                serviceType = data["serviceType"].orEmpty().trim().lowercase(),
            )
        }

        fun fromExtras(extras: Bundle?): RideOfferPayload? {
            val rideId = extras?.getString(EXTRA_RIDE_ID).orEmpty()
            if (rideId.isEmpty()) return null

            return RideOfferPayload(
                rideId = rideId,
                fare = extras?.getString(EXTRA_FARE).orEmpty(),
                pickupAddress = extras?.getString(EXTRA_PICKUP_ADDRESS).orEmpty(),
                dropAddress = extras?.getString(EXTRA_DROP_ADDRESS).orEmpty(),
                pickupDistanceKm = extras?.getString(EXTRA_PICKUP_DISTANCE).orEmpty(),
                tripDistanceKm = extras?.getString(EXTRA_TRIP_DISTANCE).orEmpty(),
                vehicleIconType = extras?.getString(EXTRA_VEHICLE_ICON_TYPE).orEmpty(),
                vehicleLabel = extras?.getString(EXTRA_VEHICLE_LABEL).orEmpty(),
                expiresInSeconds = extras?.getInt(EXTRA_EXPIRES_IN, DEFAULT_EXPIRY_SECONDS)
                    ?.takeIf { it > 0 } ?: DEFAULT_EXPIRY_SECONDS,
                riderName = extras?.getString(EXTRA_RIDER_NAME).orEmpty(),
                serviceType = extras?.getString(EXTRA_SERVICE_TYPE).orEmpty(),
            )
        }
    }
}

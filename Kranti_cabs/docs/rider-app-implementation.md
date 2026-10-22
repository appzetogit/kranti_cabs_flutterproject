# ZI CAB rider app — implementation notes

**Repo:** `Rish1811/Zicabuser` · branch `main`
**Head at time of writing:** `14f1da7`
**Backend:** `Rish1811/Zicab` · branch `main`, deployed to `https://zicab.in`

This covers the nine commits pushed to the rider app that have **never been
compiled** — there is no Dart toolchain on the machine they were written on.
Everything here is written against the live backend, which is already deployed.

---

## 1. Do this first

```bash
git pull origin main
flutter pub get
flutter analyze          # nothing here has been compiled — this is the real gate
flutter run              # or build a debug APK
```

`flutter analyze` is not a formality. Nine commits touching 25 files went in
without a compiler ever seeing them. Expect the possibility of a type error or
an unused import; none of the changes are large, and every one is listed below
with the reasoning, so a fix should be obvious rather than archaeological.

If analyze is clean, build and work through §5.

---

## 2. The commits, newest first

| Commit | What it does |
|---|---|
| `14f1da7` | Four "add to your fare" amounts during search instead of one |
| `fd1c037` | Per-ride platform fee shown and sent |
| `5c176cf` | Says why a ride can't be booked; stops showing an invented fare |
| `b645a0d` | Shows the rider how long the wait is (driver→pickup ETA) |
| `712dd87` | Routes through our backend, not the public OSRM demo server |
| `c7271b5` | Redraws the route when the driver leaves it |
| `5060b7a` | Vehicle markers on the first frame |
| `8da4177` | Stops the poll walking the driver marker backwards |
| `8ac5e49` | Prices the fleet for the zone the trip starts in |

`f27d4bd` ("necode") is Rish's own commit and sits between `fd1c037` and
`14f1da7`. `14f1da7` was written on top of it — no conflicts.

---

## 3. What changed, and why

### 3.1 Zone pricing — `8ac5e49`

**The bug:** the app asked for the vehicle catalog with no location, so every
city got Bengaluru's fares. Riders in Indore were **quoted and charged** the
wrong zone's price.

- `home_repository.dart` — `getSetPrices({lat, lng})` now sends the pickup
  coordinates. The server resolves the zone from them and returns
  `zone_id` / `zone_name` alongside the rows.
- `home_providers.dart` — `setPricesAtProvider` is keyed on the location, so
  moving the pickup pin reloads the tariff.
- `booking_state.dart` — `pricingFor` no longer falls back to *any* row when
  the vehicle has no price in this zone. A missing price is now a missing
  price.
- `booking_controller.dart` — `_reloadTariffsFor` refetches when the pickup
  changes.

**Contract:** `GET /users/set-prices?scope=ride&lat=&lng=` → rows plus
`zone_id`, `zone_name`. Without lat/lng the server falls back to global rows,
which is what produced the bug — always send them.

### 3.2 Live tracking — `8da4177`, `5060b7a`, `c7271b5`

Three separate faults in the tracking map:

- **Marker walked backwards** (`8da4177`). Two sources of truth — the socket
  push and the REST poll — were both writing the driver's position, and the
  poll's older fix sometimes landed last. `ride_tracking_controller.dart` now
  keeps a live-fix precedence: a position is only accepted if it is newer than
  the one held. Also fixes duplicate socket registrations and a provider leak
  (`autoDispose`).
- **Markers appeared late** (`5060b7a`). Icons were loaded from the network
  before the first frame. `home_providers.dart` now serves the bundled asset
  first and swaps in the remote icon when it arrives, so a marker is on screen
  immediately.
- **Stale polyline after a reroute** (`c7271b5`). `live_tracking_map.dart`
  gained `_routeSupersededByReroute`: when the driver leaves the drawn line,
  the old polyline is dropped rather than left hanging. Heading wins over
  bearing-between-points when off-route, so the vehicle icon points where the
  driver is actually facing.

### 3.3 Routing through our own backend — `712dd87`

**The problem:** the app called `router.project-osrm.org` — a public demo
server with no uptime guarantee, no rate limit we control, and every rider's
pickup and drop address sent to a third party.

- `route_api.dart` (new) — calls `POST /users/route` on our backend.
- `route_polyline_service.dart` — backend first, straight-line fallback,
  bounded in-memory cache.
- `ride_eta_service.dart` — same source, so the ETA and the drawn line agree.

**Contract:** `POST /users/route` `{origin, destination, stops}` → encoded
polyline + distance + duration. Authenticated and rate-limited. Google
Directions with an OSRM fallback, cached server-side for five minutes, so the
apps no longer each pay for their own lookup.

### 3.4 Driver→pickup ETA — `b645a0d`

`ride_tracking_controller.dart` and `ride_tracking_screen.dart` now show how
long the wait is, refreshed as the driver moves, instead of only showing the
trip leg once the ride starts.

### 3.5 Booking blockers and the invented fare — `5c176cf`

`confirm_booking_screen.dart` used to show hardcoded placeholders — ₹220, ₹30,
₹250, 12.6 km — whenever the real numbers hadn't loaded. A rider could see a
fare that was never real.

- Placeholders replaced with `--`.
- `bookingBlocker` on the controller states *why* Book is disabled
  (no price in this zone, no route, nothing selected) instead of a dead button.
- `BookingAttempt` carries the failure reason back to the screen.

### 3.6 Platform fee — `fd1c037`

`₹6.30` per ride, from admin settings, end to end: `set_price_model.dart` parses
`rider_platform_fee` / `rider_platform_fee_type`, `fare_calculator.dart` adds
it, `confirm_booking_screen.dart` shows it as its own row, `ride_repository.dart`
sends `platformFee` with the booking. The server caps it at the tariff's own
value, so the app cannot inflate it.

### 3.7 Four fare amounts during search — `14f1da7`

The card in `raise_fare_card.dart` had one button that added one step (₹10) and
then locked for the two-minute cooling-off period. A rider who already knew the
trip was worth ₹40 more needed six minutes to say so.

- `ride_bid_model.dart` — new `remainingRaiseSteps`: how many whole
  `bidStepAmount` increases still fit under `bidCeilingMaxFare`.
- `raise_fare_card.dart` — rewritten. One button per remaining step, capped at
  four: **+ ₹10 / + ₹20 / + ₹30 / + ₹40**, each showing the fare it lands on
  underneath. `onRaise` is now `ValueChanged<int>` (step count, not a bare
  callback). At the ceiling the card says so instead of offering nothing.
- `finding_driver_screen.dart` — `_raiseFare(rideId, steps)` passes the choice
  through to `raiseFare(rideId, steps: steps)`, which the repository already
  supported.

**The count is not fixed at four.** It follows the admin's settings — a trip
with two steps of headroom shows two buttons.

---

## 4. Backend behaviour the app now depends on

All of this is **already live**. No app change is needed for any of it; it is
listed because it changes what the app receives.

### 4.1 Bidding is admin-controlled

`GET /users/vehicle-types` returns `dispatch_type` per vehicle, which is what
gates the bid toggle on the confirm screen (`supportsBidding`). The server now
reports what the admin's settings actually allow, not just the vehicle's stored
value:

- Master switch off → every vehicle reports `normal`, toggle disappears.
- "Offer bidding on every vehicle" on (**currently on**) → every vehicle
  reports `both`.

Admin → **Bidding** (top-level sidebar entry).

The catalog is cached five minutes per server instance, so a settings change
takes up to that long to reach a fresh install.

### 4.2 The raise-fare card now appears without opting in

A city or parcel booking is created in `user_increment_only` mode whether or not
the rider switched bidding on beforehand, so `createdRide.bidding.isUserIncrement`
is true on ordinary bookings and the card shows during the search.

**The rider is not charged more for this.** Opting in at booking starts them at
the bid floor (+10% by current settings); this path starts at exactly the fare
they were quoted and moves only if they tap. Outstation is excluded — handing
pricing to the drivers is a different thing to opt into and still requires the
toggle.

Current live settings: step ₹10, ceiling +20%, two-minute wait between raises.

### 4.3 Driver markers are capped at 1 km

`GET /rides/available-drivers` **without** `vehicleTypeId` is the map's ambient
markers, and the server clamps it to the admin's
`nearby_driver_marker_radius` (1 km). The app asks for 2 km and gets 1 km back —
that is deliberate, not a bug.

The **same endpoint with** `vehicleTypeId` is the fare/ETA lookup ("how far is
the closest Sedan") and still gets the full 25 km range. Don't merge the two
call sites.

### 4.4 Vehicle visibility per home-screen section

`app_modules` on each vehicle in the catalog now reflects what the admin picked.
It never used to — the server dropped the field on save, so every vehicle
carried an empty list, and empty means *every section*.

`isOfferedUnderModule` in `vehicle_type_model.dart` already reads it, so nothing
in the app changes. But **the visible fleet will change** the moment the admin
starts assigning vehicles to sections: a vehicle pinned to Zi City Ride
disappears from Zi Airport, Zi Parcel and Zi Outstation.

### 4.5 One ride OTP per rider

`ride.otp` is now fixed per rider — the same four digits on every trip, Rapido
style — rather than generated per booking. Nothing in the app changes; it reads
`ride.otp` as before.

Worth knowing what it trades away: a per-ride code proves the rider is present
when the trip starts, a fixed one only proves the driver has carried them before.

### 4.6 Outstation

Vehicles now carry `enable_outstation_ride` and `support_outstation`. The app
reads exactly these two keys and the catalog never sent them, which is why the
Outstation screen was always empty.

---

## 5. What to test after the build

**Zone pricing**
1. Set the pickup in Bengaluru, note the fares. Move it to Indore. The fares
   must change, not persist.
2. A vehicle with no price row in the current zone must show `--` and Book must
   be disabled with a reason, not fall back to another zone's number.

**Tracking**
3. Watch the driver marker through a whole trip — it must never jump backwards.
4. Markers must be on screen on the first frame, not after a beat.
5. Have the driver leave the drawn route. The old line must vanish and a new one
   appear; the vehicle icon must point the way they are driving.

**Search and bidding**
6. Book an ordinary city ride without touching any bid toggle. After two
   minutes of searching, the card must appear with four amounts.
7. Tap **+ ₹30**. The fare must rise by exactly ₹30 and the countdown restart.
8. Raise repeatedly to the ceiling. The card must switch to "Still looking for
   a driver" rather than offering a button that fails.
9. Confirm the quoted fare on the confirm screen equals the fare on the search
   screen for a rider who never opted in. **They must match.**

**Map**
10. On the home map, only drivers within roughly 1 km should have markers.

**Fee**
11. The platform fee row must appear on the confirm screen and be included in
    the total.

---

## 6. Open items

- **Nothing here has been compiled.** `flutter analyze` first.
- The "no driver accepted in N seconds, now show bidding" fallback is **not**
  implemented. `_handleStateUpdated` in `ride_search_controller.dart` only
  reacts to `accepted/arriving/started/arrived` and never refreshes
  `createdRide`, so the server cannot flip a ride into bidding mid-search and
  have the app notice. §4.2 sidesteps this by setting the mode at booking
  instead; a true mid-search switch needs that listener to refresh the ride.
- `finding_driver_screen.dart:531` gates the "See driver offers" button on
  `createdRide.bidding.isDriverBid`, which is outstation only. That is correct
  today, but it shares the stale-`createdRide` problem above.

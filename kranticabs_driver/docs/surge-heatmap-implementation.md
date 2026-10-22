# Surge & Demand Heatmap — implementation plan

Goal: a Rapido-style map in the driver app that shows **where fares are
higher** (surge, e.g. `1.3x`) and **where demand is high**, so drivers move
there. Tap an area → see the hike, how long it lasts, how far it is, and
**Go to** it.

This document covers both sides. The backend half is small because most of
it already exists; the Flutter half is mostly upgrading a screen that is
already there.

---

## 0. What already exists — build on it, do not duplicate

| Piece | Where | State |
|---|---|---|
| Automatic surge engine | Backend `services/surgeService.js` | **Live.** H3 hexagons (resolution 8, ~0.7 km² each). Every minute it compares demand (riders asking for a price in a hex) with free drivers there and sets a multiplier, held for 10 min. Capped at 1.5x by admin, 2x by law. |
| Surge applied to fares | Backend `rideService` / `getSetPrices` | **Live.** The rider's quote already includes the multiplier. |
| `GET /drivers/surge-map` | Backend | **Live, but unused by the app.** Active surge hexes near the driver with outline, multiplier, minutes left. |
| `GET /drivers/heatmap` | Backend `heatmap/heatmapService.js` | **Live, used by the app.** Demand zones from recent rides — but on a **square** grid, not H3. |
| Demand map screen | App `lib/features/heatmap/` | **Live.** `/demand-map`, opened from Home. Draws demand zones, legend, zone sheet, polls on a timer and on movement. |

**The problem to solve:** the app shows demand but never fare hikes, and the
two backend maps use different grids, so they cannot be drawn together.

---

## 1. Backend (Om / Claude) — ~1.5 days

### 1.1 One endpoint for the map: `GET /api/v1/drivers/opportunity-map`

> **Live since 7 Oct 2026** (backend commit `f1141b8`). Build against it now.
> Besides the fields below it also returns: top-level `max_multiplier`;
> per cell `surge_ends_at` (ISO time, null when not surging); per hotspot
> `center` and `demand_level`; per airport `surge_ends_in_minutes`.
> With no demand anywhere, `cells` and `hotspots` are empty arrays - show
> "No surge near you".

Query: `lat`, `lng`, `radius_km` (default 8, max 25). Driver auth.

Everything on **one H3 grid** (the surge engine's), so demand and surge line
up exactly. Demand per hex comes from the counters the surge engine already
keeps — no new tracking.

```json
{
  "success": true,
  "data": {
    "refreshed_at": "2026-10-07T13:04:00Z",
    "refresh_after_seconds": 60,
    "surge_enabled": true,
    "cells": [
      {
        "hex": "8861892635fffff",
        "center": { "lat": 12.9767, "lng": 77.5713 },
        "boundary": [{ "lat": 12.97, "lng": 77.56 }],
        "multiplier": 1.3,
        "surge_ends_in_minutes": 7,
        "demand_level": "very_high",
        "demand": 14,
        "free_drivers": 3,
        "distance_km": 2.1,
        "label": "Majestic"
      }
    ],
    "hotspots": [
      {
        "hex": "8861892635fffff",
        "title": "Majestic",
        "multiplier": 1.3,
        "distance_km": 2.1,
        "example_fare": { "km": 5, "normal": 149, "now": 194, "vehicle": "Kranti Cab Non-AC" }
      }
    ],
    "airports": [
      { "name": "Kempegowda International Airport", "lat": 13.1986, "lng": 77.7066,
        "demand_level": "high", "multiplier": 1.0, "distance_km": 31.4 }
    ]
  }
}
```

Field rules:
- `cells`: every hex in range with **either** a surge (`multiplier > 1`)
  **or** demand above "normal". Max 150, nearest first. Empty list = quiet.
- `demand_level`: `normal | high | very_high`, server-decided (thresholds stay
  server-side, like today's heatmap).
- `multiplier`: `1.0` when demand is high but no surge.
- `label`: nearest known area name (reverse-geocoded once per hex, cached in
  Redis for a day). May be empty — show the distance instead.
- `hotspots`: top 3 by multiplier, then demand — drives the "Go to" button.
- `example_fare`: what a 5 km trip in **this driver's** vehicle type pays now
  vs normally, from the live tariff for that hex's zone. Lets the app say
  "₹45 more per 5 km trip" instead of a bare `1.3x`.
- `airports`: from the admin's Airport list, so airport demand shows even
  when far away (airport queues are a big reason drivers relocate).

`/drivers/heatmap` and `/drivers/surge-map` stay as they are, so current app
builds keep working.

### 1.2 "Surge near you" push

When a hex starts surging at ≥ 1.2x, push to **online, free** drivers within
5 km of it:

> **1.3x fares at Majestic** — 2.1 km away, for the next 10 min

- At most one per driver per 15 minutes; never to a driver on a trip.
- Opens the app straight on the map, centred on that hex.
- Admin toggle + radius + minimum multiplier, next to the existing surge
  settings.

### 1.3 Guard rails (backend)

- Multipliers already capped (admin 1.5x, legal 2x) — the map shows exactly
  the multiplier the rider is quoted, never a separate "driver" number.
- Riders' identities and exact pickups never leave the server — only counts
  per hex, as today.

---

## 2. Driver app (Flutter) — ~4–6 days

### 2.1 Data layer

- `lib/features/heatmap/data/opportunity_models.dart` — `OpportunityCell`,
  `Hotspot`, `AirportDemand`, `OpportunityMap` (parse the JSON above; every
  field optional-safe).
- `heatmap_repository.dart` — add `getOpportunityMap(lat, lng, radiusKm)`
  calling `/drivers/opportunity-map`. Add the path to `ApiConstants`.
- Reuse `heatmap_controller.dart`'s refresh logic as is: poll every
  `refresh_after_seconds` while visible, refresh on a 3 s debounce after the
  map moves far, **stop when the app is in the background**.

### 2.2 Home screen overlay (matches the screenshot)

On the Home map, while **on duty**:
- Draw each cell's `boundary` as a polygon:
  - surge cells: orange→red fill by multiplier (1.1x light, 1.5x+ strong),
    30–40% opacity, with a **`1.3x` pill marker** at `center`.
  - high-demand, no surge: soft purple/blue fill, no pill.
- Chips row above the bottom sheet: **Go to** · **Surge** · **High Demand** ·
  **Airport**. Surge / High Demand / Airport are filters (toggle layers).
- **Go to**: opens the best `hotspot` sheet (2.4). If none: "No surge near
  you right now — demand is normal."
- Keep it light: max 150 polygons; reuse `BitmapDescriptor`s for pills
  (cache by text); do not redraw if `refreshed_at` did not change.

### 2.3 Full-screen map (`/demand-map`)

Switch it from `/drivers/heatmap` to `/drivers/opportunity-map`; same
layers and chips as Home, plus the legend (update `heatmap_legend.dart`:
normal / high demand / surge 1.1x–1.5x+). Airports as markers with their
demand badge.

### 2.4 Cell / hotspot sheet (tap a hex)

Replace `demand_zone_sheet.dart` content with:
- Title: `label` or "2.1 km away"
- Big: **1.3x fares** (or "High demand" when 1.0x)
- "Ends in 7 min" countdown — recompute locally every second from
  `surge_ends_in_minutes` + `refreshed_at`; at 0 say "Surge ended".
- "14 riders looking · 3 drivers free"
- "**₹194** for a 5 km trip (normally ₹149)" from `example_fare`
- **Navigate** → Google Maps turn-by-turn to `center`:
  `google.navigation:q=<lat>,<lng>&mode=d` (fallback
  `https://www.google.com/maps/dir/?api=1&destination=<lat>,<lng>`).
- Small print: *"Surge can end before you arrive. You are paid the fare the
  rider is quoted when they book."*

### 2.5 Push handling

On the "surge near you" push: open Home (or `/demand-map`) centred on the
hex in the payload, sheet open. Ignore it if the driver is on a trip.

---

## 3. Things to get right

- **Never show a multiplier the rider is not charged.** The map reads the
  same Redis value the fare quote uses — do not compute or round
  differently in the app.
- **Countdowns drift**: base them on server `refreshed_at`, not phone time
  alone, and refresh on resume.
- **Location off / offline**: show the map without the "distance" lines and
  a one-line prompt to turn location on; never block going on duty.
- **Battery**: no polling in the background; no polling faster than 30 s.
- **Many drivers chasing one hex**: the engine already cools a surge as free
  drivers arrive (supply rises → multiplier drops). The push cap (1.2)
  stops everyone being sent at once.

---

## 4. Testing

1. Admin → Surge settings: lower the trigger for a test, request quotes from
   a test rider account at one pickup repeatedly → that hex should turn
   1.1x+ within a minute.
2. Driver app: hex appears with pill; tap → sheet shows multiplier,
   countdown, example fare; **Navigate** opens Google Maps.
3. Rider app quote for a pickup inside that hex shows the same multiplier.
4. Wait for `hold_minutes` → hex disappears; sheet says "Surge ended".
5. Push: online free test driver within 5 km gets one alert, not a second
   within 15 min; driver on a trip gets none.
6. Location off: map loads, prompt shown, no crash.

---

## 5. Order of work

| # | Who | What | Est. |
|---|---|---|---|
| 1 | Backend | `/drivers/opportunity-map` (H3, demand + surge + airports + example fare) | 1 day |
| 2 | Flutter | Models + repository + switch `/demand-map` to the new endpoint | 1 day |
| 3 | Flutter | Home overlay: polygons, pills, chips, Go to | 1.5–2 days |
| 4 | Flutter | Cell sheet + navigation + countdown | 1 day |
| 5 | Backend | Surge-near-you push + admin toggles | 0.5 day |
| 6 | Flutter | Push deep-link to the hex | 0.5 day |
| 7 | Both | Test checklist above on a real phone | 0.5 day |

Steps 1 and 2 can start together: the JSON shape above is the contract.
Ask before changing it.

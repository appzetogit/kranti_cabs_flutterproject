# Ride Voice Announcements

In-ride spoken announcements for the Zi Cab rider app, in the rider's own
language, with the wording and timings managed from the admin panel.

The feature is strictly additive. If the config API is down, if there is no ETA,
if the device has no speech engine — the trip books, tracks, completes and pays
exactly as it did before. Nothing in the ride path awaits anything here.

---

## Flow

### Welcome

```
Driver starts trip  (RIDE_STARTED — not booking, not acceptance, not arrival)
        ↓
Scheduler armed, ride.startedAt recorded
        ↓
Every 30s: now − startedAt ≥ welcome.delay_minutes ?
        ↓ yes
Fetch remaining ETA  ──── unavailable ───→ retry next tick (max 10, then skip)
        ↓
Read rider's app language  (localeProvider)
        ↓
Pick backend template for that language  (→ fallback_language → any configured)
        ↓
Replace {minutes} with the live ETA
        ↓
TTS speaks it in the matching locale  (en-IN / hi-IN / kn-IN)
        ↓
welcomePlayed = true, persisted against this ride id
```

### Arrival

```
Every 30s while the trip runs
        ↓
arrivalPlayed == false ?
        ↓ yes
Remaining ETA ≤ arrival.trigger_remaining_minutes ?
        ↓ yes
Generate localized message, speak it
        ↓
arrivalPlayed = true, persisted
        ↓
Both played → ticker stops; no further timers, no further ETA lookups
```

---

## Why it is not a 5-minute `Timer`

Android suspends processes, kills them under memory pressure, and throttles
timers under battery optimisation. A `Timer(Duration(minutes: 5), …)` is the one
mechanism that cannot be trusted for this.

Instead every tick re-derives the answer from two durable facts:

| Fact | Where it lives | Survives |
|---|---|---|
| `ride.startedAt` | the ride record on the server | anything |
| `welcomePlayed` / `arrivalPlayed` | Hive, keyed by ride id | process death |

So a trip that was backgrounded, screen-locked, or force-killed and relaunched
reaches exactly the conclusion it would have reached had the app stayed open —
including "that was already said, don't say it again".

Three entry points re-run the check: the 30s ticker, `AppLifecycleState.resumed`,
and app start (`resumeActiveRide()` looks for a trip already in progress).

### Background / lock screen — what actually happens

- **Foreground:** works.
- **Backgrounded, screen locked, process alive:** works. Android TTS speaks over
  the lock screen; no wake lock or extra permission is involved.
- **Process killed by the OS:** nothing is spoken while it is dead. On next
  launch the scheduler re-arms from the active ride and speaks anything still
  due, exactly once.

No foreground service was added. The app has no background service today, and
the brief was explicit about not creating a competing one or requesting
permissions the feature does not need. If hard guarantees are wanted while the
process is dead, the right follow-up is a server-side scheduled push rather than
a client timer — the backend already knows `startedAt` and the ETA.

---

## Language

There is **one** language preference, and the voice follows it. No separate
voice-language setting exists, by design.

```
Rider picks a language (first-run screen, or Settings → Language)
        ↓
localeProvider  →  Hive 'locale_code'
        ↓                       ↓
MaterialApp.locale        voice: template lookup + TTS locale
```

| App language | TTS locale |
|---|---|
| en | en-IN |
| hi | hi-IN |
| kn | kn-IN |
| ta | ta-IN |
| te | te-IN |

Two independent fallbacks, so a gap never means silence *and* never means
mismatched voice and text:

1. **Text:** no template for the rider's language → `fallback_language` → any
   configured language.
2. **Voice:** the resolved *text* language decides the TTS locale, and if that
   locale is not installed on the device the engine falls back to `en-IN`.

Changing language mid-trip applies to the next announcement — the scheduler
reads the preference at speak time, not at arm time.

---

## Backend

No new model, no new route, no migration. `ride_voice` is a new section on the
existing `AdminAppSetting` document, which is how `wallet_setting` and
`tip_setting` already work.

| Method | Path | Auth |
|---|---|---|
| `GET` | `/api/v1/users/settings/ride-voice` | public |
| `GET` | `/api/v1/admin/general-settings/ride-voice` | admin |
| `PATCH` | `/api/v1/admin/general-settings/ride-voice` | admin |

Both GET routes already existed generically; registering the category was a
one-line map entry.

**Files**

| File | Change |
|---|---|
| `admin/data/defaultRideVoiceSettings.js` | new — shipped defaults, the approved en/hi/kn copy |
| `admin/models/AdminAppSetting.js` | `ride_voice: Mixed` |
| `admin/data/defaultAppSettings.js` | seeds `ride_voice` on a fresh install |
| `admin/services/adminService.js` | category mapping, defaults merge on read, validation on write |
| `frontend/.../settings/RideVoiceSettings.jsx` | new — admin editor |
| `frontend/src/routes/lazyPages.js`, `adminRoutes.jsx`, `AdminLayout.jsx` | route + nav entry |

**Read** merges the stored section over the shipped defaults. That is what makes
the endpoint answer usefully on an install whose settings document predates the
feature, and what stops an admin who edits only the Hindi wording from blanking
English and Kannada.

**Write** replaces the section wholesale (so a language can actually be deleted)
after sanitising: booleans coerced, numbers clamped (`delay_minutes` 0–120,
`trigger_remaining_minutes` 1–120, rate/pitch/volume to their real ranges), and
non-string message values dropped — the app calls `.replace()` on these and a
number there would throw on a live trip.

**Response shape**

```json
{
  "success": true,
  "data": {
    "settings": {
      "enabled": true,
      "fallback_language": "en",
      "welcome": {
        "enabled": true,
        "delay_minutes": 5,
        "messages": { "en": "… approximately {minutes} minutes. Thank you.", "hi": "…", "kn": "…" }
      },
      "arrival": {
        "enabled": true,
        "trigger_remaining_minutes": 10,
        "messages": { "en": "…", "hi": "…", "kn": "…" }
      },
      "speech": { "rate": 0.5, "pitch": 1, "volume": 1 }
    }
  }
}
```

`messages` is a free-form map keyed by the same codes the apps already use.
Adding Marathi is a new key — never a schema change, never an app release.

### Variables

Templates support `{variable}`. Only `{minutes}` is substituted today. An
unknown placeholder is left in the text rather than blanked, so a variable added
in the panel before the app understands it shows up obviously in testing instead
of silently swallowing a word. Adding `{destination}` later is one entry in the
map passed to `renderVoiceTemplate`.

The arrival copy uses `{minutes}` rather than a literal "10" so that changing the
threshold in the panel cannot leave the sentence contradicting the trigger. At
the default of 10 the spoken text is identical to the approved wording.

---

## Flutter

```
lib/features/ride/voice/
  data/
    ride_voice_config.dart           model + template rendering + fallbacks
    ride_voice_repository.dart       GET the config, cache the last good copy
    ride_voice_progress_store.dart   per-ride "already said" flags (Hive)
    ride_voice_log.dart              [RideVoice] logging, debug builds only
  services/
    ride_tts_service.dart            flutter_tts wrapper, one reused engine
    ride_eta_service.dart            remaining ETA
  application/
    ride_voice_scheduler.dart        the state machine
    ride_voice_providers.dart        Riverpod wiring + rider on/off switch
```

### ETA

Reuses the routing provider the map already draws with (OSRM), asking for the
leg from the driver's current position to the destination — no second vendor, no
extra key, no new permission.

1. Live route: driver's last known position → destination.
2. Falls back to the booking's own estimate minus elapsed time since start.
3. Otherwise **null** — and null is honoured. Speaking a wrong number is worse
   than saying nothing, so the announcement retries on later ticks and is
   eventually skipped rather than guessed.

Results are memoised for 45s keyed on the rounded driver position, so the 30s
ticker averages roughly one lightweight request per 45s and only while an
announcement is still pending.

### Duplicate prevention

`welcomePlayed` / `arrivalPlayed` are written to Hive against the ride id before
the next tick can run, and an `_evaluating` guard stops two overlapping ticks
from both reading "not played yet" while the first is awaiting the ETA call. A
TTS failure still marks the announcement handled — retrying a broken engine every
30 seconds for the rest of the trip helps nobody.

The arrival announcement fires on the first crossing of the threshold and never
again, so an ETA drifting 10.5 → 10.2 → 9.8 → 9.5 produces exactly one
announcement.

### Lifecycle

Completed, cancelled or failed → ticker cancelled, TTS stopped mid-sentence,
listeners cleared, stored progress removed. A rider cancelling from the tracking
screen is reported directly, because that path never produces a "cancelled" ride
update. A new ride id resets everything, so the second trip of the day announces
itself exactly like the first.

### Scope

App-scoped, not screen-scoped: a rider who backs out to Home mid-trip still gets
their announcements. When the tracking screen stops feeding updates the scheduler
re-reads the ride itself after 75s.

---

## Files changed in the app

**New**

```
lib/features/ride/voice/**                       (7 files, above)
lib/features/onboarding/presentation/language_select_screen.dart
lib/l10n/app_{en,hi,kn,ta,te}.arb
l10n.yaml
test/ride_voice_config_test.dart
```

**Modified**

| File | Change |
|---|---|
| `pubspec.yaml` | `flutter_tts`, `flutter_localizations`, `intl` → 0.20.2, `generate: true` |
| `lib/app/app.dart` | `locale`, `supportedLocales`, `localizationsDelegates` |
| `lib/app/router.dart` | `/language` route |
| `lib/main.dart` | `resumeActiveRide()` on start |
| `lib/features/splash/presentation/splash_screen.dart` | first run → language screen |
| `lib/features/profile/application/locale_provider.dart` | normalisation, `appLocaleProvider`, `languageChosenProvider` |
| `lib/features/profile/presentation/language_screen.dart` | localized |
| `lib/features/settings/presentation/settings_screen.dart` | localized + voice on/off switch |
| `lib/features/ride/application/ride_tracking_controller.dart` | 2 hooks, both in `try/catch` |
| `lib/core/constants/storage_keys.dart` | 4 keys |
| `android/app/src/main/AndroidManifest.xml` | `<queries>` for `TTS_SERVICE` — package visibility, **not** a permission |

No permission was added. No existing screen was redesigned. The only change to
the ride flow is two guarded calls in the tracking controller.

---

## Security

Device TTS, not a cloud voice: there is no API key to keep off the phone, no
per-ETA audio file to generate or store, and it works with no signal. If a cloud
voice is ever wanted, its secret stays on the backend and the app keeps calling
the same config endpoint.

Logs are `[RideVoice]`-prefixed, debug-only, and carry timings, language codes
and state names — never addresses, phone numbers or ride ids.

---

## Test status

`flutter test test/ride_voice_config_test.dart` — 9/9 passing, including parsing
the verbatim production payload and rendering the approved wording in all three
languages.

`flutter analyze lib` — 0 errors. `flutter build apk --debug` — succeeds.

The backend save path was round-tripped against production: a partial payload
persisted, a non-string message was rejected, a Hindi-only edit left English and
Kannada intact, and the defaults were restored afterwards.

Timing, locale-specific voice output and lock-screen behaviour need a device.

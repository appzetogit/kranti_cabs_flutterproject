# KrantiCabs Rider

The KrantiCabs driver app: going online, receiving and accepting ride offers,
running trips, and tracking earnings. Flutter, talking to
`https://kranticabs.com/api/v1`.

Android package and iOS bundle ID: `com.kranticabs.delivery`.

## Run

```bash
flutter pub get
flutter run
```

```bash
flutter analyze
flutter test
```

## Before a release

These need accounts this repo has no access to, so they can't be done in code.

1. **iOS push notifications.** Add the iOS app `com.kranticabs.delivery` to the
   Firebase project `kranticabs-2cfd1`, then put its `GoogleService-Info.plist` in
   `ios/Runner` and add it to the Runner target in Xcode (or run
   `flutterfire configure`). Upload an APNs key under Project settings → Cloud
   Messaging. Without the plist the app still runs, but logs
   "Firebase failed to initialise" and never receives a ride request.
2. **API keys.** Restrict the Maps key (`AndroidManifest.xml`,
   `ios/Runner/AppDelegate.swift`) and the Firebase keys to package / bundle ID
   `com.kranticabs.delivery` and the release signing certificate, and allow only
   the APIs each one calls.
3. **Support contact.** Set `supportPhone` and `supportEmail` in
   `lib/core/constants/app_constants.dart`. The Help Center's contact card
   stays hidden until at least one is set.
4. **Play Console declarations.** Each needs a short explanation and a video:
   - Foreground service, location: live location while the driver is online or
     on a trip, including while Google Maps navigation is open.
   - Full-screen intent, display over other apps, ignore battery optimisations:
     the lock-screen ride-offer card.

## Location in the background

Navigation opens Google Maps, which puts this app in the background for most
of every trip. `LocationService.watchPosition(keepAliveInBackground: true)`
keeps location flowing while the driver is online or on a trip:

- **Android:** runs geolocator's location foreground service, with an ongoing
  "Sharing your location" notification. It only needs while-in-use location
  permission, so the app does not ask for background location.
- **iOS:** uses the `location` background mode and shows the blue location
  indicator while the app is in the background.

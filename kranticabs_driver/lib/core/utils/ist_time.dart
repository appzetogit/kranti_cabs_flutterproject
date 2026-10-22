/// India has one fixed offset (UTC+5:30, no DST), so a manual offset is all
/// that's needed — no `timezone` package/IANA database required.
///
/// The backend always sends UTC ISO strings; `DateTime.toLocal()` would
/// convert to the *device's* zone instead, which is wrong for a driver
/// travelling outside India. Subscription times must always read as IST.
library;

const _istOffset = Duration(hours: 5, minutes: 30);

/// Converts a UTC [DateTime] to India Standard Time for display.
///
/// The result keeps `isUtc == true` (it's just shifted), which is fine
/// since callers only ever read its fields for formatting — never compare
/// it against `DateTime.now()`.
DateTime toIst(DateTime utc) => utc.toUtc().add(_istOffset);

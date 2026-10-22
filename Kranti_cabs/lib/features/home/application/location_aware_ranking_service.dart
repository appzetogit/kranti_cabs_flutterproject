import 'dart:math' as math;

/// One destination-search candidate to rank, decoupled from whichever
/// provider (Google Places, Nominatim, Photon, or the native geocoding
/// fallback — see `search_destination_screen.dart`) produced it, so this
/// file has no dependency on that screen's own private result model.
class SearchRankCandidate {
  /// Position in the list the provider itself returned it in — used as this
  /// candidate's text/relevance signal. Providers already do their own
  /// relevance scoring (Google Autocomplete's own ranking, Nominatim's
  /// `importance`); re-deriving that client-side with a hand-rolled fuzzy
  /// matcher would just be a worse copy of work already done, so their
  /// order is trusted and only nudged by proximity/locality/exact-match on
  /// top of it — see the class doc on [rankSearchResults].
  final int providerRank;

  final String title;
  final String address;

  /// Null when the provider didn't return coordinates up front — Google
  /// Autocomplete predictions don't carry geometry, only Place Details
  /// does, and that's deliberately not fetched for every candidate just to
  /// rank them (that would be a Place Details call per keystroke's worth of
  /// results, which is exactly the API-cost blow-up this is meant to avoid).
  /// Ranking degrades gracefully without it: see [rankSearchResults].
  final double? lat;
  final double? lng;

  const SearchRankCandidate({
    required this.providerRank,
    required this.title,
    required this.address,
    this.lat,
    this.lng,
  });
}

/// Tunable weights/thresholds for [rankSearchResults], kept in one place
/// rather than scattered magic numbers, and constructor-overridable so a
/// unit test can isolate one signal at a time.
class LocationAwareRankingConfig {
  // Distance buckets (meters) -> proximity score. Wide, generous buckets on
  // purpose: this nudges nearby results up the list, it never hides a
  // genuinely distant one — the exact-match and provider-rank terms below
  // can, and often should, outweigh it (a major airport several km away
  // should still beat a closer unrelated result).
  final double bucket2kmScore;
  final double bucket5kmScore;
  final double bucket10kmScore;
  final double bucket25kmScore;
  final double bucket100kmScore;

  /// Applied instead of the buckets above once a candidate is genuinely far
  /// — a different city/region entirely, not just the other side of town.
  /// Negative on purpose: confirmed by a live device test where a place
  /// literally named "Hospital" 946km away (Phagwara, Punjab) outranked
  /// real nearby hospitals for a plain "hospital" search, because the exact-
  /// text-match bonus alone comfortably beat a flat zero. A generic-word
  /// coincidence that far away should lose to a real nearby result; a
  /// genuinely intended distant destination ("Bhopal", "Mumbai Airport")
  /// still surfaces fine because nothing closer is competing for that exact
  /// query — see the "Test 3"-style case in the test file.
  final double veryFarPenalty;

  /// Distance (meters) beyond which [veryFarPenalty] applies instead of
  /// [bucket100kmScore].
  final double veryFarThresholdMeters;

  final double exactMatchBonus;
  final double startsWithBonus;
  final double containsWordBonus;

  final double localityMatchBonus;
  final double cityMatchBonus;

  /// Points lost per position further down the provider's own list a
  /// candidate sits — keeps their relevance ordering as a real signal
  /// instead of being wiped out by the bonuses above.
  final double providerRankPenaltyPerStep;

  /// Above this GPS accuracy (meters), the current fix is treated as too
  /// unreliable to bias ranking with at all — proximity/locality scoring is
  /// skipped entirely rather than nudging results toward a wrong guess of
  /// where the rider actually is.
  final double maxTrustedAccuracyMeters;

  const LocationAwareRankingConfig({
    this.bucket2kmScore = 40,
    this.bucket5kmScore = 28,
    this.bucket10kmScore = 16,
    this.bucket25kmScore = 6,
    this.bucket100kmScore = 0,
    this.veryFarPenalty = -30,
    this.veryFarThresholdMeters = 100000,
    this.exactMatchBonus = 60,
    this.startsWithBonus = 30,
    this.containsWordBonus = 12,
    this.localityMatchBonus = 22,
    this.cityMatchBonus = 10,
    this.providerRankPenaltyPerStep = 3,
    this.maxTrustedAccuracyMeters = 100,
  });

  double proximityScoreFor(double distanceMeters) {
    if (distanceMeters <= 2000) return bucket2kmScore;
    if (distanceMeters <= 5000) return bucket5kmScore;
    if (distanceMeters <= 10000) return bucket10kmScore;
    if (distanceMeters <= 25000) return bucket25kmScore;
    if (distanceMeters <= veryFarThresholdMeters) return bucket100kmScore;
    return veryFarPenalty;
  }
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMeters = 6371000.0;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lng2 - lng1) * math.pi / 180;
  final a =
      math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(dLambda / 2) *
          math.sin(dLambda / 2);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

/// True if [needle] appears in [haystack] as a whole word/phrase rather than
/// as a substring of some other word — "vijay" should match "Vijay Nagar",
/// not the middle of an unrelated longer word.
bool _containsWord(String haystack, String needle) {
  if (needle.isEmpty) return false;
  final pattern = RegExp('(^|[^a-z0-9])${RegExp.escape(needle)}([^a-z0-9]|\$)');
  return pattern.hasMatch(haystack);
}

/// Re-orders [candidates] (as a list of original indices, ranked best
/// first) to prefer results that are textually relevant to [query] AND
/// geographically/contextually close to the rider — without ever hiding a
/// genuinely distant, exact match.
///
/// [currentLat]/[currentLng]/[currentAccuracyMeters]/[currentLocality]/
/// [currentCity] may all be null or missing — no GPS fix yet, permission
/// denied, reverse-geocode not resolved yet — in which case ranking falls
/// back to provider order + exact-match only, exactly like before this
/// existed. Search must keep working either way.
List<int> rankSearchResults({
  required String query,
  required List<SearchRankCandidate> candidates,
  double? currentLat,
  double? currentLng,
  double? currentAccuracyMeters,
  String? currentLocality,
  String? currentCity,
  LocationAwareRankingConfig config = const LocationAwareRankingConfig(),
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final normalizedLocality = currentLocality?.trim().toLowerCase();
  final normalizedCity = currentCity?.trim().toLowerCase();
  final locationIsTrustworthy =
      currentLat != null &&
      currentLng != null &&
      (currentAccuracyMeters == null ||
          currentAccuracyMeters <= config.maxTrustedAccuracyMeters);

  final scored = <MapEntry<int, double>>[];
  for (var i = 0; i < candidates.length; i++) {
    final candidate = candidates[i];
    final title = candidate.title.trim().toLowerCase();
    final address = candidate.address.trim().toLowerCase();
    double score =
        -(candidate.providerRank * config.providerRankPenaltyPerStep);

    if (normalizedQuery.isNotEmpty) {
      if (title == normalizedQuery) {
        score += config.exactMatchBonus;
      } else if (title.startsWith(normalizedQuery)) {
        score += config.startsWithBonus;
      } else if (_containsWord(title, normalizedQuery)) {
        score += config.containsWordBonus;
      }
    }

    if (locationIsTrustworthy &&
        candidate.lat != null &&
        candidate.lng != null) {
      final distance = _haversineMeters(
        currentLat,
        currentLng,
        candidate.lat!,
        candidate.lng!,
      );
      score += config.proximityScoreFor(distance);
    }

    if (normalizedLocality != null &&
        normalizedLocality.isNotEmpty &&
        (title.contains(normalizedLocality) ||
            address.contains(normalizedLocality))) {
      score += config.localityMatchBonus;
    }
    if (normalizedCity != null &&
        normalizedCity.isNotEmpty &&
        (title.contains(normalizedCity) || address.contains(normalizedCity))) {
      score += config.cityMatchBonus;
    }

    scored.add(MapEntry(i, score));
  }

  // Sorted explicitly by (score desc, original index asc) rather than
  // relying on List.sort's stability, so ties always keep the provider's
  // own relative order instead of it being an implementation detail.
  scored.sort((a, b) {
    final cmp = b.value.compareTo(a.value);
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  });

  return scored.map((e) => e.key).toList();
}

/// Shared with the search screen so it doesn't need its own haversine helper
/// just to show "X km away" next to a result whose coordinates are known.
double distanceMetersBetween(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) => _haversineMeters(lat1, lng1, lat2, lng2);

import 'package:flutter_test/flutter_test.dart';
import 'package:taxiuser/features/home/application/location_aware_ranking_service.dart';

// Vijay Nagar Square, Indore — used as "the rider's current location" across
// these cases, matching the brief's own example.
const _vijayNagarLat = 22.7534;
const _vijayNagarLng = 75.8937;

void main() {
  group('rankSearchResults', () {
    test(
      'Test 1 — generic search ("hospital") prefers nearby over distant',
      () {
        final candidates = [
          // Provider lists this one first, but it's on the far side of the
          // city — ranking should still pull the nearer one above it.
          const SearchRankCandidate(
            providerRank: 0,
            title: 'City Hospital',
            address: 'Rau, Indore',
            lat: 22.62,
            lng: 75.78, // ~18km away
          ),
          const SearchRankCandidate(
            providerRank: 1,
            title: 'Apollo Hospital',
            address: 'Vijay Nagar, Indore',
            lat: 22.755,
            lng: 75.895, // ~0.3km away
          ),
        ];

        final order = rankSearchResults(
          query: 'hospital',
          candidates: candidates,
          currentLat: _vijayNagarLat,
          currentLng: _vijayNagarLng,
          currentLocality: 'Vijay Nagar',
          currentCity: 'Indore',
        );

        expect(order.first, 1, reason: 'the nearby hospital should rank first');
      },
    );

    test('Test 2 — exact locality match ranks very prominently', () {
      final candidates = [
        const SearchRankCandidate(
          providerRank: 0,
          title: 'Vijay Nagar Chowk',
          address: 'Some other city',
          lat: 26.9,
          lng: 80.9, // far away, unrelated place sharing a word
        ),
        const SearchRankCandidate(
          providerRank: 1,
          title: 'Vijay Nagar',
          address: 'Vijay Nagar, Indore, Madhya Pradesh',
          lat: 22.753,
          lng: 75.893,
        ),
      ];

      final order = rankSearchResults(
        query: 'Vijay Nagar',
        candidates: candidates,
        currentLat: _vijayNagarLat,
        currentLng: _vijayNagarLng,
        currentLocality: 'Vijay Nagar',
        currentCity: 'Indore',
      );

      expect(
        order.first,
        1,
        reason:
            'the exact "Vijay Nagar" match should outrank a same-word, unrelated, distant result',
      );
    });

    test('Test 3 — a distant valid destination stays discoverable', () {
      // Only one candidate: a real result far from Indore. It must not be
      // dropped or scored so low it would never be shown — ranking only
      // reorders a candidate list, it never filters one out.
      final candidates = [
        const SearchRankCandidate(
          providerRank: 0,
          title: 'Bhopal',
          address: 'Bhopal, Madhya Pradesh',
          lat: 23.2599,
          lng: 77.4126, // ~185km from Vijay Nagar
        ),
      ];

      final order = rankSearchResults(
        query: 'Bhopal',
        candidates: candidates,
        currentLat: _vijayNagarLat,
        currentLng: _vijayNagarLng,
        currentCity: 'Indore',
      );

      expect(order, [
        0,
      ], reason: 'the only candidate must still be returned, not dropped');
    });

    test(
      'Test 4 — exact-name destination outranks a closer unrelated result',
      () {
        final candidates = [
          const SearchRankCandidate(
            providerRank: 0,
            title: 'Random Tea Stall',
            address: 'Near Vijay Nagar, Indore',
            lat: 22.754,
            lng: 75.894, // very close
          ),
          const SearchRankCandidate(
            providerRank: 1,
            title: 'Indore Airport',
            address: 'Devi Ahilyabai Holkar Airport, Indore',
            lat: 22.7218,
            lng: 75.8011, // several km away
          ),
        ];

        final order = rankSearchResults(
          query: 'Indore Airport',
          candidates: candidates,
          currentLat: _vijayNagarLat,
          currentLng: _vijayNagarLng,
          currentCity: 'Indore',
        );

        expect(
          order.first,
          1,
          reason:
              'exact name relevance must beat a closer but unrelated result',
        );
      },
    );

    test(
      'Test 5 — no current location: search still ranks by text + provider order',
      () {
        final candidates = [
          const SearchRankCandidate(
            providerRank: 0,
            title: 'Some Place',
            address: 'Somewhere',
          ),
          const SearchRankCandidate(
            providerRank: 1,
            title: 'Query Match',
            address: 'Somewhere else',
          ),
        ];

        final order = rankSearchResults(
          query: 'Query Match',
          candidates: candidates,
          // currentLat/currentLng intentionally omitted — GPS unavailable.
        );

        expect(
          order.first,
          1,
          reason: 'exact match still wins with no location at all',
        );
      },
    );

    test('Test 6 — poor GPS accuracy disables proximity bias entirely', () {
      final candidates = [
        // Closer to the (unreliable) fix, but provider ranked it second.
        const SearchRankCandidate(
          providerRank: 1,
          title: 'Nearby Result',
          address: 'Somewhere close',
          lat: 22.7535,
          lng: 75.8938,
        ),
        const SearchRankCandidate(
          providerRank: 0,
          title: 'Farther Result',
          address: 'Somewhere else',
          lat: 22.9,
          lng: 76.1,
        ),
      ];

      final withGoodAccuracy = rankSearchResults(
        query: 'result',
        candidates: candidates,
        currentLat: _vijayNagarLat,
        currentLng: _vijayNagarLng,
        currentAccuracyMeters: 10,
      );
      final withBadAccuracy = rankSearchResults(
        query: 'result',
        candidates: candidates,
        currentLat: _vijayNagarLat,
        currentLng: _vijayNagarLng,
        currentAccuracyMeters: 5000, // way past maxTrustedAccuracyMeters
      );

      // With a trustworthy fix, proximity can flip the provider's own order.
      expect(withGoodAccuracy.first, 0);
      // With an untrustworthy fix, proximity contributes nothing, so the
      // provider's own order (index 1 ranked first) is preserved instead.
      expect(withBadAccuracy.first, 1);
    });

    test(
      'regression: a same-word exact match ~950km away must not outrank a '
      'real nearby result — found via a live device test where searching '
      '"hospital" from Vijay Nagar surfaced a place literally named '
      '"Hospital" in Phagwara, Punjab (946.6km) above actual nearby hospitals',
      () {
        final candidates = [
          // Nominatim's top hit: exact text match, but a world away.
          const SearchRankCandidate(
            providerRank: 0,
            title: 'Hospital',
            address: 'Hospital, Phagwara, Phagwara Tahsil, Kapurthala, Punjab',
            lat: 31.22,
            lng: 75.77, // ~946km from Vijay Nagar, Indore
          ),
          // A real, nearby hospital — only a partial (word) text match.
          const SearchRankCandidate(
            providerRank: 2,
            title: 'Apollo Hospital',
            address: 'Vijay Nagar, Indore',
            lat: 22.755,
            lng: 75.895, // ~0.3km away
          ),
        ];

        final order = rankSearchResults(
          query: 'hospital',
          candidates: candidates,
          currentLat: _vijayNagarLat,
          currentLng: _vijayNagarLng,
          currentLocality: 'Vijay Nagar',
          currentCity: 'Indore',
        );

        expect(
          order.first,
          1,
          reason:
              'the real nearby hospital must outrank a coincidental exact-word match 946km away',
        );
      },
    );

    test('distance buckets: closer of two equally-relevant results wins', () {
      final candidates = [
        const SearchRankCandidate(
          providerRank: 0,
          title: 'Restaurant',
          address: 'Rau, Indore',
          lat: 22.62,
          lng: 75.78, // ~18km
        ),
        const SearchRankCandidate(
          providerRank: 0,
          title: 'Restaurant',
          address: 'Vijay Nagar, Indore',
          lat: 22.755,
          lng: 75.895, // ~0.3km
        ),
      ];

      final order = rankSearchResults(
        query: 'restaurant',
        candidates: candidates,
        currentLat: _vijayNagarLat,
        currentLng: _vijayNagarLng,
      );

      expect(order, [1, 0], reason: 'equal text relevance -> nearer one wins');
    });
  });
}

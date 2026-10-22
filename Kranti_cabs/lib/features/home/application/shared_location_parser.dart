import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';

/// A place pulled out of something the rider shared or tapped in another app.
class SharedPlace {
  final double lat;
  final double lng;

  /// A name carried by the link itself ("Cafe Coffee Day"), when it has one.
  final String? label;

  const SharedPlace({required this.lat, required this.lng, this.label});
}

final _latLng = r'(-?\d{1,3}(?:\.\d+)?)';
final _pairOnly = RegExp('^\\s*$_latLng\\s*,\\s*$_latLng\\s*(?:\\((.*)\\))?\\s*\$');
final _atPair = RegExp('@$_latLng,$_latLng');
final _dataPair = RegExp('!3d$_latLng!4d$_latLng');
final _urlInText = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
// Runs to the end of the line, not the next space: a geo label can contain
// spaces - geo:0,0?q=22.7,75.8(Palasia Square).
final _geoInText = RegExp(r'geo:[^\r\n<>"]+', caseSensitive: false);

const _shortLinkHosts = {'maps.app.goo.gl', 'goo.gl'};

bool _valid(double lat, double lng) =>
    lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);

SharedPlace? _fromPair(RegExpMatch? match, {String? label}) {
  if (match == null) return null;
  final lat = double.tryParse(match.group(1) ?? '');
  final lng = double.tryParse(match.group(2) ?? '');
  if (lat == null || lng == null || !_valid(lat, lng)) return null;
  return SharedPlace(lat: lat, lng: lng, label: label);
}

/// Turns whatever Android handed us - a `geo:` URI, a Google Maps link, or a
/// block of shared text that contains one - into coordinates.
///
/// Returns null when there is no location in it. Short links
/// (maps.app.goo.gl/...) hide the coordinates behind a redirect, so those cost
/// one network round trip; everything else is parsed locally.
Future<SharedPlace?> parseSharedLocation(String raw) async {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final geo = _geoInText.firstMatch(text)?.group(0);
  if (geo != null) {
    final place = await _parseGeoUri(geo);
    if (place != null) return place;
  }

  final url = _urlInText.firstMatch(text)?.group(0);
  if (url != null) {
    // Trailing punctuation from a sentence ("...see https://maps.app.goo.gl/x.")
    final cleaned = url.replaceAll(RegExp(r'[).,;]+$'), '');
    return _parseWebUrl(cleaned);
  }

  return _fromPair(_pairOnly.firstMatch(text));
}

Future<SharedPlace?> _parseGeoUri(String geo) async {
  final uri = Uri.tryParse(geo);
  if (uri == null) return null;

  String? label;
  final q = uri.queryParameters['q'];
  if (q != null) {
    final labelled = RegExp(r'^(.*?)\((.*)\)\s*$').firstMatch(q);
    if (labelled != null) label = labelled.group(2);
  }

  final fromPath = _fromPair(_pairOnly.firstMatch(uri.path), label: label);
  if (fromPath != null) return fromPath;

  if (q == null || q.trim().isEmpty) return null;

  final fromQuery = _fromPair(_pairOnly.firstMatch(q), label: label);
  if (fromQuery != null) return fromQuery;

  // "geo:0,0?q=221B Baker Street" - an address, not a coordinate.
  try {
    final results = await locationFromAddress(q.trim());
    if (results.isEmpty) return null;
    final first = results.first;
    if (!_valid(first.latitude, first.longitude)) return null;
    return SharedPlace(lat: first.latitude, lng: first.longitude, label: q.trim());
  } catch (_) {
    return null;
  }
}

Future<SharedPlace?> _parseWebUrl(String url, {int depth = 0}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final local = _parseMapsUrl(uri);
  if (local != null) return local;

  if (depth >= 1 || !_shortLinkHosts.contains(uri.host.toLowerCase())) {
    return null;
  }
  return _resolveShortLink(uri);
}

SharedPlace? _parseMapsUrl(Uri uri) {
  final whole = Uri.decodeFull(uri.toString());

  // The pin itself (!3d..!4d..) is more exact than the map centre (@..),
  // which is only where the viewport happens to be.
  final label = _placeNameFromPath(uri);
  final fromData = _fromPair(_dataPair.firstMatch(whole), label: label);
  if (fromData != null) return fromData;

  for (final key in const ['q', 'query', 'daddr', 'destination', 'll', 'center']) {
    final value = uri.queryParameters[key];
    if (value == null) continue;
    final place = _fromPair(_pairOnly.firstMatch(value), label: label);
    if (place != null) return place;
  }

  return _fromPair(_atPair.firstMatch(whole), label: label);
}

String? _placeNameFromPath(Uri uri) {
  final segments = uri.pathSegments;
  final i = segments.indexOf('place');
  if (i == -1 || i + 1 >= segments.length) return null;
  final name = Uri.decodeComponent(segments[i + 1]).replaceAll('+', ' ').trim();
  return name.isEmpty || _pairOnly.hasMatch(name) ? null : name;
}

/// Follows a maps.app.goo.gl / goo.gl/maps redirect to the full Google Maps
/// URL, which is the one that carries the coordinates.
Future<SharedPlace?> _resolveShortLink(Uri shortLink) async {
  try {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        followRedirects: true,
        maxRedirects: 6,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/120.0 Mobile Safari/537.36',
        },
      ),
    );
    final response = await dio.getUri<String>(shortLink);
    var finalUri = response.realUri;

    // Google sometimes interposes a consent page that carries the real
    // destination in `continue`.
    if (finalUri.host.contains('consent.google')) {
      final next = finalUri.queryParameters['continue'];
      final nextUri = next == null ? null : Uri.tryParse(next);
      if (nextUri != null) finalUri = nextUri;
    }

    final fromUrl = _parseMapsUrl(finalUri);
    if (fromUrl != null) return fromUrl;

    final body = response.data ?? '';
    return _fromPair(_dataPair.firstMatch(body)) ?? _fromPair(_atPair.firstMatch(body));
  } catch (_) {
    return null;
  }
}

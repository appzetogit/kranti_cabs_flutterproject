/// Defensive readers for anything that came off the network.
///
/// Every one of these exists because the alternative — `data as Map<String,
/// dynamic>` — throws a `_TypeError` the moment an endpoint returns null, an
/// error envelope, or a list where an object was expected. That is not a
/// hypothetical: a backend deploy that changes a response shape, or a 200 with
/// an empty body, will crash a screen mid-use.
///
/// These never throw. A malformed value becomes an empty map, an empty list, or
/// the caller's fallback, and the screen renders empty instead of dying.
library;

/// A JSON object, or an empty map for anything else.
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

/// A JSON array, or an empty list for anything else.
List<dynamic> asList(dynamic value) {
  if (value is List) return value;
  return const <dynamic>[];
}

/// Every element of [value] read as a JSON object, skipping anything that is
/// not one. Use for `results` arrays, where one bad row should not lose the
/// other forty.
List<Map<String, dynamic>> asMapList(dynamic value) {
  return asList(value)
      .map(asMap)
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

/// The `results` array of a paginated envelope, whether the payload is the
/// envelope itself or already the bare array.
List<Map<String, dynamic>> asResults(dynamic value, {String key = 'results'}) {
  if (value is List) return asMapList(value);
  return asMapList(asMap(value)[key]);
}

/// A number from a value the API may send as int, double, or string.
double asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? fallback;
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? fallback;
}

/// A trimmed string, empty for null.
String asText(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

bool asBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text.isEmpty) return fallback;
  return !['0', 'false', 'no', 'off', 'null'].contains(text);
}

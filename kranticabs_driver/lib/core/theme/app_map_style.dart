/// Google Maps styling shared across driver app screens.
class AppMapStyle {
  AppMapStyle._();

  /// Clean, modern light map style — hides commercial POI noise, softens
  /// land/road colors, and keeps route polylines and markers readable.
  /// Matches the rider app's style so both sides of a ride look the same.
  static const String light = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f2f4f7"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#6b7280"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca3af"}]},
  {"featureType": "poi", "stylers": [{"visibility": "simplified"}]},
  {"featureType": "poi", "elementType": "labels.text", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#e6f4ea"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#e5e7eb"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#4b5563"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#d0e3ff"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#93c5fd"}]}
]
''';

  static const String dark = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#757575"}]},
  {"featureType": "administrative.country", "elementType": "labels.text.fill", "stylers": [{"color": "#9e9e9e"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#bdbdbd"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#181818"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8a8a8a"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#373737"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3c3c3c"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry", "stylers": [{"color": "#4e4e4e"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "transit", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit.line", "elementType": "geometry", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "transit.station", "elementType": "geometry", "stylers": [{"color": "#3a3a3a"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#3d3d3d"}]}
]
''';

  static const String muted = dark;
}

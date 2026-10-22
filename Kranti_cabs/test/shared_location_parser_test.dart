import 'package:flutter_test/flutter_test.dart';
import 'package:taxiuser/features/home/application/shared_location_parser.dart';

void main() {
  void expectPlace(SharedPlace? place, double lat, double lng, {String? label}) {
    expect(place, isNotNull);
    expect(place!.lat, closeTo(lat, 1e-6));
    expect(place.lng, closeTo(lng, 1e-6));
    if (label != null) expect(place.label, label);
  }

  test('geo URI with coordinates in the path', () async {
    expectPlace(await parseSharedLocation('geo:22.7196,75.8577'), 22.7196, 75.8577);
  });

  test('WhatsApp-style geo URI with 0,0 and a labelled q', () async {
    expectPlace(
      await parseSharedLocation('geo:0,0?q=22.7196,75.8577(Palasia Square)'),
      22.7196,
      75.8577,
      label: 'Palasia Square',
    );
  });

  test('Google Maps ?q=lat,lng link', () async {
    expectPlace(
      await parseSharedLocation('https://maps.google.com/?q=22.7196,75.8577'),
      22.7196,
      75.8577,
    );
  });

  test('place URL prefers the pin (!3d!4d) over the map centre (@)', () async {
    expectPlace(
      await parseSharedLocation(
        'https://www.google.com/maps/place/Rajwada/@22.7180,75.8550,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d22.7196!4d75.8577',
      ),
      22.7196,
      75.8577,
      label: 'Rajwada',
    );
  });

  test('@lat,lng only', () async {
    expectPlace(
      await parseSharedLocation('https://www.google.com/maps/@22.7196,75.8577,15z'),
      22.7196,
      75.8577,
    );
  });

  test('link inside a sentence with trailing punctuation', () async {
    expectPlace(
      await parseSharedLocation('Meet me here: https://maps.google.com/?q=22.7196,75.8577.'),
      22.7196,
      75.8577,
    );
  });

  test('negative longitude and no location', () async {
    expectPlace(
      await parseSharedLocation('https://maps.google.com/?q=40.7128,-74.0060'),
      40.7128,
      -74.0060,
    );
    expect(await parseSharedLocation('hello there'), isNull);
    expect(await parseSharedLocation('geo:0,0'), isNull);
  });
}

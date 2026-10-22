import 'package:flutter_test/flutter_test.dart';
import 'package:taxiuser/core/utils/json_safe.dart';

/// Each case here is a payload shape that used to crash a screen.
///
/// `data as Map<String, dynamic>` throws a `_TypeError` on null, on a list, and
/// on the `Map<dynamic, dynamic>` that some decoders hand back — all of which
/// arrive from a real backend during an error, an empty result, or a shape
/// change. These helpers must absorb every one of them.
void main() {
  group('asMap', () {
    test('survives the shapes that used to throw', () {
      expect(asMap(null), isEmpty);
      expect(asMap('a string'), isEmpty);
      expect(asMap(42), isEmpty);
      expect(asMap(<dynamic>[1, 2]), isEmpty);
    });

    test('accepts a loosely typed map', () {
      final loose = <dynamic, dynamic>{'name': 'Zi', 'fare': 120};
      expect(asMap(loose)['name'], 'Zi');
      expect(asMap(loose)['fare'], 120);
    });
  });

  group('asResults', () {
    test('reads a paginated envelope', () {
      final payload = {
        'results': [
          {'id': '1'},
          {'id': '2'},
        ],
      };
      expect(asResults(payload).length, 2);
      expect(asResults(payload).first['id'], '1');
    });

    test('reads a bare array too', () {
      expect(asResults([{'id': '1'}]).length, 1);
    });

    test('returns empty rather than throwing on junk', () {
      expect(asResults(null), isEmpty);
      expect(asResults({'results': null}), isEmpty);
      expect(asResults({'results': 'nope'}), isEmpty);
      expect(asResults('nope'), isEmpty);
    });

    test('one bad row does not lose the good ones', () {
      final payload = {
        'results': [
          {'id': '1'},
          'not an object',
          {'id': '3'},
        ],
      };
      expect(asResults(payload).map((e) => e['id']).toList(), ['1', '3']);
    });
  });

  group('scalar readers', () {
    test('numbers arrive as int, double or string', () {
      expect(asDouble(12), 12.0);
      expect(asDouble(12.5), 12.5);
      expect(asDouble('12.5'), 12.5);
      expect(asDouble(null), 0);
      expect(asDouble('abc', 7), 7);
      expect(asInt('9'), 9);
      expect(asInt(null, 3), 3);
    });

    test('text is trimmed and never null', () {
      expect(asText('  hello  '), 'hello');
      expect(asText(null), '');
      expect(asText('', 'fallback'), 'fallback');
      expect(asText(0), '0');
    });

    test('booleans accept the truthy spellings an API might send', () {
      expect(asBool(true), isTrue);
      expect(asBool('1'), isTrue);
      expect(asBool('yes'), isTrue);
      expect(asBool('0'), isFalse);
      expect(asBool('false'), isFalse);
      expect(asBool(null), isFalse);
      expect(asBool(null, true), isTrue);
    });
  });
}

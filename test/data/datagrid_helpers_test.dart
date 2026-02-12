import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/data/datagrid_helpers.dart';

void main() {
  group('datagrid helpers', () {
    test('getNestedMapValue returns direct and nested values', () {
      final map = <String, dynamic>{
        'qty': 5,
        'required_attributes': {'part_type': 'resistor', 'value': '10k'},
      };

      expect(getNestedMapValue(map, 'qty'), 5);
      expect(
        getNestedMapValue(map, 'required_attributes.part_type'),
        'resistor',
      );
      expect(getNestedMapValue(map, 'required_attributes.missing'), isNull);
    });

    test('getNestedMapValue returns null when path traverses non-map', () {
      final map = <String, dynamic>{'required_attributes': 'not-a-map'};
      expect(getNestedMapValue(map, 'required_attributes.value'), isNull);
    });

    test('setNestedMapValue sets direct and nested values', () {
      final map = <String, dynamic>{'qty': 1};

      setNestedMapValue(map, 'qty', 10);
      expect(map['qty'], 10);

      setNestedMapValue(map, 'required_attributes.value', '100n');
      expect(map['required_attributes'], isA<Map<String, dynamic>>());
      expect(
        (map['required_attributes'] as Map<String, dynamic>)['value'],
        '100n',
      );
    });

    test('setNestedMapValue creates missing intermediate maps', () {
      final map = <String, dynamic>{};
      setNestedMapValue(map, 'a.b.c', 42);
      expect(
        (map['a'] as Map<String, dynamic>)['b'],
        isA<Map<String, dynamic>>(),
      );
      expect(
        ((map['a'] as Map<String, dynamic>)['b'] as Map<String, dynamic>)['c'],
        42,
      );
    });
  });
}

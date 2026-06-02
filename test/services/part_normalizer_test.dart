import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/part_normalizer.dart';

void main() {
  group('PartNormalizer', () {
    test('normalizePartType resolves aliases', () {
      expect(PartNormalizer.normalizePartType('cap'), 'capacitor');
      expect(PartNormalizer.normalizePartType('RES'), 'resistor');
      expect(PartNormalizer.normalizePartType('u'), 'ic');
      expect(PartNormalizer.normalizePartType('connector'), 'connector');
    });

    test('normalizeValue handles embedded notation', () {
      expect(PartNormalizer.normalizeValue('2u2'), '2.2u');
      expect(PartNormalizer.normalizeValue('100nF'), '100n');
      expect(PartNormalizer.normalizeValue('4k7'), '4.7k');
      expect(PartNormalizer.normalizeValue('5k1'), '5.1k');
      expect(PartNormalizer.normalizeValue('24k9'), '24.9k');
      expect(PartNormalizer.normalizeValue('422k'), '422k');
    });

    test('valuesLikelyEqual compares canonical numeric values', () {
      expect(
        PartNormalizer.valuesLikelyEqual(
          a: '0.01m',
          b: '10u',
          partType: 'capacitor',
        ),
        isTrue,
      );
      expect(
        PartNormalizer.valuesLikelyEqual(
          a: '4k7',
          b: '4.7k',
          partType: 'resistor',
        ),
        isTrue,
      );
      expect(
        PartNormalizer.valuesLikelyEqual(
          a: '100n',
          b: '1u',
          partType: 'capacitor',
        ),
        isFalse,
      );
    });

    test('canonicalPartNumber strips separators/case', () {
      expect(PartNormalizer.canonicalPartNumber('ABC-123_xY'), 'abc123xy');
    });
  });
}

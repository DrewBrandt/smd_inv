import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/services/digikey_part_resolver.dart';

void main() {
  group('DigiKeyPartResolver', () {
    test('prefers stored DigiKey PN field', () {
      final result = DigiKeyPartResolver.resolveFromInventoryData({
        FirestoreFields.digiKeyPartNumber: '497-15115-1-ND',
        FirestoreFields.vendorLink:
            'https://www.digikey.com/en/products/result?keywords=OTHER-ND',
      });

      expect(result, '497-15115-1-ND');
    });

    test('extracts imported DigiKey PN from notes', () {
      final result = DigiKeyPartResolver.resolveFromInventoryData({
        FirestoreFields.notes: 'Incoming | DigiKey PN: 296-BQ25306RTERCT-ND',
      });

      expect(result, '296-BQ25306RTERCT-ND');
    });

    test('builds encoded search URL', () {
      expect(
        DigiKeyPartResolver.searchUrl('STM32C011F6U6TR UFQFPN'),
        'https://www.digikey.com/en/products/result?keywords=STM32C011F6U6TR+UFQFPN',
      );
    });
  });
}

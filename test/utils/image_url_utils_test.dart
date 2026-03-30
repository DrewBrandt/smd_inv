import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/utils/image_url_utils.dart';

void main() {
  group('normalizeBoardImageUrl', () {
    test('adds https when scheme is missing', () {
      expect(
        normalizeBoardImageUrl('example.com/images/board.png'),
        'https://example.com/images/board.png',
      );
    });

    test('trims whitespace and encodes spaces', () {
      expect(
        normalizeBoardImageUrl('  https://example.com/my board image.jpg  '),
        'https://example.com/my%20board%20image.jpg',
      );
    });

    test('returns null for empty or invalid values', () {
      expect(normalizeBoardImageUrl(''), isNull);
      expect(normalizeBoardImageUrl('   '), isNull);
      expect(normalizeBoardImageUrl('http://'), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/cart_paste_parser.dart';

void main() {
  group('CartPasteParser', () {
    test('parses DigiKey cart export rows', () {
      const text =
          '"Index","Quantity","Part Number","Manufacturer Part Number","Description","Customer Reference","Available","Backorder","Unit Price","Extended Price USD"\n'
          '"1","2","497-15115-1-ND","STM32F303CBT6","IC MCU 32BIT","","2","0","3.25","6.50"\n';

      final lines = CartPasteParser.parse(text);

      expect(lines, hasLength(1));
      expect(lines.single.partNumber, 'STM32F303CBT6');
      expect(lines.single.digikeyPartNumber, '497-15115-1-ND');
      expect(lines.single.description, 'IC MCU 32BIT');
      expect(lines.single.quantity, 2);
    });

    test('parses app exported DigiKey CSV rows', () {
      const text =
          'DigiKey Part Number,Manufacturer Part Number,Quantity,Customer Reference,Description,Vendor Link\n'
          '296-12345-1-ND,CUSTOM-REG,5,Manual,Regulator,\n';

      final lines = CartPasteParser.parse(text);

      expect(lines, hasLength(1));
      expect(lines.single.partNumber, 'CUSTOM-REG');
      expect(lines.single.digikeyPartNumber, '296-12345-1-ND');
      expect(lines.single.quantity, 5);
    });

    test('parses loose quick-order lines', () {
      const text = '''
497-15115-1-ND, 3
5 296-12345-1-ND
''';

      final lines = CartPasteParser.parse(text);

      expect(lines, hasLength(2));
      expect(lines[0].digikeyPartNumber, '497-15115-1-ND');
      expect(lines[0].quantity, 3);
      expect(lines[1].digikeyPartNumber, '296-12345-1-ND');
      expect(lines[1].quantity, 5);
    });
  });
}

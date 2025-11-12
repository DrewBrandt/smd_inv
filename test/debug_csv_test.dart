import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/csv_parser_service.dart';

void main() {
  test('Debug fuzzy match', () {
    const csv = 'Item Name,Qty,Link URL\n'
        'Capacitor,100,https://example.com';

    final result = CsvParserService.parse(
      csv,
      expectedColumns: ['Item', 'Quantity', 'Link'],
    );

    print('Success: ${result.success}');
    print('Headers: ${result.headers}');
    print('Column map: ${result.columnMap}');
    print('Has Item: ${result.hasColumn('Item')}');
    print('Has Quantity: ${result.hasColumn('Quantity')}');
    print('Has Link: ${result.hasColumn('Link')}');
    print('Data rows: ${result.dataRows}');

    expect(result.hasColumn('Quantity'), true);
  });
}

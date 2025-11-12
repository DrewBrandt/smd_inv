import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/csv_parser_service.dart';

void main() {
  group('CsvParserService', () {
    group('parse() - Basic parsing', () {
      test('parses comma-separated CSV with header', () {
        const csv = '''Item,Quantity,Link,Notes,Price Per Unit
Capacitor 10uF,100,https://example.com,Test note,\$0.50
Resistor 10k,200,https://example.com/r,Another note,\$0.10''';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Link', 'Notes', 'Price Per Unit'],
        );

        expect(result.success, true);
        expect(result.dataRows.length, 2);
        expect(result.headers.length, 5);
        expect(result.delimiter, ',');
      });

      test('parses tab-separated TSV with header', () {
        const tsv = 'Item\tQuantity\tLink\tNotes\n'
            'Capacitor 10uF\t100\thttps://example.com\tTest note\n'
            'Resistor 10k\t200\thttps://example.com/r\tAnother note';

        final result = CsvParserService.parse(
          tsv,
          expectedColumns: ['Item', 'Quantity', 'Link', 'Notes'],
        );

        expect(result.success, true);
        expect(result.dataRows.length, 2);
        expect(result.delimiter, '\t');
      });

      test('auto-detects tab delimiter over comma', () {
        const tsv = 'Item\tQuantity\tLink\n'
            'Cap, 10uF\t100\thttps://example.com';

        final result = CsvParserService.parse(
          tsv,
          expectedColumns: ['Item', 'Quantity', 'Link'],
        );

        expect(result.success, true);
        expect(result.delimiter, '\t');
        expect(result.dataRows.length, 1);
      });

      test('handles CSV without header row', () {
        const csv = 'Capacitor 10uF,100,https://example.com\n'
            'Resistor 10k,200,https://example.com/r';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Link'],
        );

        expect(result.success, true);
        // Should treat all rows as data when no header detected
        expect(result.dataRows.length, 2);
      });

      test('returns error for empty input', () {
        final result = CsvParserService.parse(
          '',
          expectedColumns: ['Item'],
        );

        expect(result.success, false);
        expect(result.error, contains('Empty input'));
      });

      test('returns error for whitespace-only input', () {
        final result = CsvParserService.parse(
          '   \n  \n  ',
          expectedColumns: ['Item'],
        );

        expect(result.success, false);
        expect(result.error, contains('Empty input'));
      });
    });

    group('parse() - Column mapping', () {
      test('maps columns by exact name match', () {
        const csv = 'Item,Quantity,Notes\n'
            'Capacitor,100,Test';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Notes'],
        );

        expect(result.hasColumn('Item'), true);
        expect(result.hasColumn('Quantity'), true);
        expect(result.hasColumn('Notes'), true);
        expect(result.columnMap['Item'], 0);
        expect(result.columnMap['Quantity'], 1);
        expect(result.columnMap['Notes'], 2);
      });

      test('maps columns by fuzzy match (contains)', () {
        const csv = 'Item Name,Quantity Info,Link URL\n'
            'Capacitor,100,https://example.com';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Link'],
        );

        // Should fuzzy match: "Item Name" contains "Item"
        expect(result.hasColumn('Item'), true);
        // Should match: "Quantity Info" contains "Quantity"
        expect(result.hasColumn('Quantity'), true);
        // Should match: "Link" in "Link URL"
        expect(result.hasColumn('Link'), true);
      });

      test('handles case-insensitive matching', () {
        const csv = 'ITEM,quantity,NoTeS\n'
            'Capacitor,100,Test';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Notes'],
        );

        expect(result.hasColumn('Item'), true);
        expect(result.hasColumn('Quantity'), true);
        expect(result.hasColumn('Notes'), true);
      });
    });

    group('getCellValue()', () {
      test('retrieves cell value by column name', () {
        const csv = 'Item,Quantity,Notes\n'
            'Capacitor,100,Test note\n'
            'Resistor,200,Another';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Notes'],
        );

        final firstRow = result.dataRows[0];
        expect(result.getCellValue(firstRow, 'Item'), 'Capacitor');
        expect(result.getCellValue(firstRow, 'Quantity'), '100');
        expect(result.getCellValue(firstRow, 'Notes'), 'Test note');

        final secondRow = result.dataRows[1];
        expect(result.getCellValue(secondRow, 'Item'), 'Resistor');
      });

      test('returns default value for missing column', () {
        const csv = 'Item,Quantity\n'
            'Capacitor,100';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Notes'],
        );

        final row = result.dataRows[0];
        expect(
          result.getCellValue(row, 'Notes', defaultValue: 'N/A'),
          'N/A',
        );
      });

      test('returns default value for out-of-bounds column', () {
        const csv = 'Item,Quantity\n'
            'Capacitor,100';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Extra'],
        );

        final row = result.dataRows[0];
        expect(result.getCellValue(row, 'Extra'), '');
      });

      test('trims whitespace from cell values', () {
        const csv = 'Item,Quantity\n'
            '  Capacitor  ,  100  ';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity'],
        );

        final row = result.dataRows[0];
        expect(result.getCellValue(row, 'Item'), 'Capacitor');
        expect(result.getCellValue(row, 'Quantity'), '100');
      });
    });

    group('getColumnValues()', () {
      test('returns all values for a column', () {
        const csv = 'Item,Quantity\n'
            'Capacitor,100\n'
            'Resistor,200\n'
            'Inductor,50';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity'],
        );

        final items = result.getColumnValues('Item');
        expect(items, ['Capacitor', 'Resistor', 'Inductor']);

        final quantities = result.getColumnValues('Quantity');
        expect(quantities, ['100', '200', '50']);
      });

      test('returns empty list for missing column', () {
        const csv = 'Item,Quantity\n'
            'Capacitor,100';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity'],
        );

        final values = result.getColumnValues('MissingColumn');
        expect(values, isEmpty);
      });
    });

    group('Real-world CSV examples', () {
      test('parses DigiKey export format', () {
        const digikey = '''Item,Quantity,Link,Notes,Price Per Unit
Capacitor 10uF 0805 X7R 25V,100,https://www.digikey.com/detail/samsung/CL21A106KQFNNNE/3887874,Bulk order,\$0.05
Resistor 10k 0603 1%,500,https://www.digikey.com/detail/yageo/RC0603FR-0710KL/726688,Standard,\$0.01''';

        final result = CsvParserService.parse(
          digikey,
          expectedColumns: ['Item', 'Quantity', 'Link', 'Notes', 'Price Per Unit'],
        );

        expect(result.success, true);
        expect(result.dataRows.length, 2);

        final firstRow = result.dataRows[0];
        expect(
          result.getCellValue(firstRow, 'Item'),
          contains('Capacitor'),
        );
        expect(result.getCellValue(firstRow, 'Quantity'), '100');
        expect(
          result.getCellValue(firstRow, 'Price Per Unit'),
          '\$0.05',
        );
      });

      test('parses Excel paste with tabs', () {
        const excel = 'Item\tQuantity\tLink\tNotes\n'
            'Capacitor 10uF\t100\thttps://example.com\tFrom Excel\n'
            'Resistor 10k\t200\thttps://example.com/r\tPasted';

        final result = CsvParserService.parse(
          excel,
          expectedColumns: ['Item', 'Quantity', 'Link', 'Notes'],
        );

        expect(result.success, true);
        expect(result.delimiter, '\t');
        expect(result.dataRows.length, 2);

        final firstRow = result.dataRows[0];
        expect(result.getCellValue(firstRow, 'Notes'), 'From Excel');
      });

      test('handles CSV with quoted fields containing commas', () {
        const csv = 'Item,Quantity,Notes\n'
            '"Capacitor, 10uF, 0805",100,"Test, with, commas"\n'
            'Resistor 10k,200,Simple note';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Notes'],
        );

        expect(result.success, true);
        expect(result.dataRows.length, 2);

        final firstRow = result.dataRows[0];
        // CSV parser should handle quoted fields correctly
        expect(
          result.getCellValue(firstRow, 'Item'),
          contains('Capacitor'),
        );
      });

      test('handles empty cells gracefully', () {
        const csv = 'Item,Quantity,Notes\n'
            'Capacitor,,\n'
            ',200,Note only\n'
            'Complete,300,All fields';

        final result = CsvParserService.parse(
          csv,
          expectedColumns: ['Item', 'Quantity', 'Notes'],
        );

        expect(result.success, true);
        expect(result.dataRows.length, 3);

        final row1 = result.dataRows[0];
        expect(result.getCellValue(row1, 'Item'), 'Capacitor');
        expect(result.getCellValue(row1, 'Quantity'), '');
        expect(result.getCellValue(row1, 'Notes'), '');

        final row2 = result.dataRows[1];
        expect(result.getCellValue(row2, 'Item'), '');
        expect(result.getCellValue(row2, 'Quantity'), '200');
      });
    });
  });
}

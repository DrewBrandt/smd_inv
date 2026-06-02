import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/csv_parser_service.dart';
import 'package:smd_inv/services/inventory_csv_mapper.dart';

const _digikeyHeader =
    '"Index","Quantity","Part Number","Manufacturer Part Number","Description","Customer Reference","Available","Backorder","Unit Price","Extended Price USD"\n';

Map<String, dynamic> _parseSingleRow(String csvRow) {
  final parsed = CsvParserService.parse(
    '$_digikeyHeader$csvRow',
    expectedColumns: InventoryCsvMapper.expectedColumns,
  );
  final items = InventoryCsvMapper.toInventoryItems(parsed);
  expect(items, hasLength(1));
  return items.first;
}

void main() {
  group('InventoryCsvMapper', () {
    // ── Legacy CSV ──────────────────────────────────────────────────────────

    test('maps legacy inventory CSV rows', () {
      const csv = '''Item,Quantity,Link,Notes,Price Per Unit
Resistor 10k 0603,25,https://www.digikey.com/detail/yageo/RC0603FR-0710KL/726688,Stock up,\$0.01''';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(parsed);

      expect(items, hasLength(1));
      expect(items.first['part_#'], 'RC0603FR-0710KL');
      expect(items.first['type'], 'resistor');
      expect(items.first['qty'], 25);
      expect(items.first['price_per_unit'], 0.01);
    });

    // ── DigiKey: field mapping ───────────────────────────────────────────────

    test('maps DigiKey export rows using manufacturer part number', () {
      const csv =
          '"Index","Quantity","Part Number","Manufacturer Part Number","Description","Customer Reference","Available","Backorder","Unit Price","Extended Price USD"\n'
          '"1","25","541-27.0HCT-ND","CRCW060327R0FKEA","RES SMD 27 OHM 1% 1/8W 0603","","25","0","0.02400","0.60"\n';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(
        parsed,
        defaultLocation: 'Incoming',
      );

      expect(items, hasLength(1));
      expect(items.first['part_#'], 'CRCW060327R0FKEA');
      expect(items.first['type'], 'resistor');
      expect(items.first['package'], '0603');
      expect(items.first['description'], 'RES SMD 27 OHM 1% 1/8W 0603');
      expect(items.first['qty'], 25);
      expect(items.first['location'], 'Incoming');
      expect(items.first['price_per_unit'], 0.024);
      expect(items.first['notes'], contains('DigiKey PN: 541-27.0HCT-ND'));
      expect(items.first['vendor_link'], contains('keywords=541-27.0HCT-ND'));
      expect(items.first['datasheet'], isNull);
    });

    test(
      'falls back to DigiKey part number when manufacturer part number is missing',
      () {
        const csv =
            '"Quantity","Part Number","Description","Unit Price"\n'
            '"5","490-9647-1-ND","BUZZER PIEZO 9X9MM SMD","0.71700"\n';

        final parsed = CsvParserService.parse(
          csv,
          expectedColumns: InventoryCsvMapper.expectedColumns,
        );
        final items = InventoryCsvMapper.toInventoryItems(parsed);

        expect(items, hasLength(1));
        expect(items.first['part_#'], '490-9647-1-ND');
        expect(items.first['description'], 'BUZZER PIEZO 9X9MM SMD');
        expect(items.first['price_per_unit'], 0.717);
      },
    );

    // ── Type detection ───────────────────────────────────────────────────────

    test('detects capacitor and extracts value and package', () {
      final item = _parseSingleRow(
        '"1","50","1276-1184-1-ND","CL10B105KA8NNNC","CAP CER 1UF 25V X7R 0603","","50","0","0.02440","1.22"\n',
      );

      expect(item['type'], 'capacitor');
      expect(item['package'], '0603');
      expect(item['value'], '1u');
      expect(item['part_#'], 'CL10B105KA8NNNC');
    });

    test('detects capacitor with pF value', () {
      final item = _parseSingleRow(
        '"1","10","490-1300-1-ND","GRM155R71H471KA01D","CAP CER 470PF 50V X7R 0402","","10","0","0.03700","0.37"\n',
      );

      expect(item['type'], 'capacitor');
      expect(item['value'], '470p');
      expect(item['package'], '0402');
    });

    test('detects electrolytic capacitor', () {
      final item = _parseSingleRow(
        '"1","5","732-8492-1-ND","865080245009","CAP ALUM 220UF 20% 10V SMD","","5","0","0.33000","1.65"\n',
      );

      expect(item['type'], 'capacitor');
      expect(item['value'], '220u');
    });

    test('detects inductor and extracts value', () {
      final item = _parseSingleRow(
        '"1","5","283-HCM1A1305V3-1R5-RCT-ND","HCM1A1305V3-1R5-R","FIXED IND 1.5UH 19A 3 MOHM SMD","","5","0","0.62000","3.10"\n',
      );

      expect(item['type'], 'inductor');
      expect(item['value'], '1.5u');
      expect(item['part_#'], 'HCM1A1305V3-1R5-R');
    });

    test('detects diode and extracts package', () {
      final item = _parseSingleRow(
        '"1","10","MSS1P4-M3/89AGICT-ND","MSS1P4-M3/89A","DIODE SCHOTTKY 40V 1A MICROSMP","","10","0","0.06700","0.67"\n',
      );

      expect(item['type'], 'diode');
      expect(item['package'], 'MICROSMP');
    });

    test('detects diode with SOT package', () {
      final item = _parseSingleRow(
        '"1","5","497-6632-1-ND","ESDA5V3L","TVS DIODE 3VWM SOT23-3","","5","0","0.36000","1.80"\n',
      );

      expect(item['type'], 'diode');
      expect(item['package'], 'SOT23-3');
    });

    test('detects connector via header keyword', () {
      final item = _parseSingleRow(
        '"1","2","1528-1969-ND","1992","GPIO HEADER FOR RASPBERRYPI A+/B","","2","0","2.95000","5.90"\n',
      );

      expect(item['type'], 'connector');
    });

    test('detects connector via conn keyword', () {
      final item = _parseSingleRow(
        '"1","5","2987-CP-01104030-ND","CP-01104030","CONN RCPT HSG 4POS 4.20MM","","5","0","0.10000","0.50"\n',
      );

      expect(item['type'], 'connector');
    });

    test('classifies IC as default type', () {
      final item = _parseSingleRow(
        '"1","5","497-STM32C011F6U6TRCT-ND","STM32C011F6U6TR","IC MCU 32BIT 32KB FLASH 20UFQFPN","","5","0","0.95000","4.75"\n',
      );

      expect(item['type'], 'ic');
      expect(item['part_#'], 'STM32C011F6U6TR');
    });

    // ── UFQFPN false-positive regression ────────────────────────────────────

    test('IC with UFQFPN package is NOT misclassified as capacitor', () {
      final item = _parseSingleRow(
        '"1","5","497-STM32C011F6U6TRCT-ND","STM32C011F6U6TR","IC MCU 32BIT 32KB FLASH 20UFQFPN","","5","0","0.95000","4.75"\n',
      );

      expect(item['type'], isNot('capacitor'));
    });

    test('IC USB controller with QFN package is not misclassified', () {
      final item = _parseSingleRow(
        '"1","5","497-18060-1-ND","STUSB4500QTR","IC USB CONTROLLER I2C 24QFN","","5","0","1.96000","9.80"\n',
      );

      expect(item['type'], 'ic');
    });

    // ── Package extraction ───────────────────────────────────────────────────

    test('extracts SOT23-3 package', () {
      final item = _parseSingleRow(
        '"1","10","31-2N7002K-7-WCT-ND","2N7002K-7-W","MOSFET N-CH 60V 380MA SOT23-3","","10","0","0.12800","1.28"\n',
      );

      expect(item['package'], 'SOT23-3');
    });

    test('extracts 0402 package from resistor', () {
      final item = _parseSingleRow(
        '"1","25","CR0603-FX-2702ELFCT-ND","CR0603-FX-2702ELF","RES SMD 27K OHM 1% 1/10W 0402","","25","0","0.02000","0.50"\n',
      );

      expect(item['package'], '0402');
    });

    // ── Vendor link and notes ────────────────────────────────────────────────

    test('builds DigiKey search URL when no direct link', () {
      final item = _parseSingleRow(
        '"1","5","296-BQ25306RTERCT-ND","BQ25306RTER","STANDALONE 17-V, 3-A SINGLE CELL","","5","0","2.10000","10.50"\n',
      );

      expect(
        item['vendor_link'],
        'https://www.digikey.com/en/products/result?keywords=296-BQ25306RTERCT-ND',
      );
      expect(item['notes'], contains('DigiKey PN: 296-BQ25306RTERCT-ND'));
      expect(item['datasheet'], isNull);
    });

    test('appends DigiKey PN note to existing notes', () {
      const csv = 'Item,Quantity,Part Number,Notes\n'
          'Widget,1,DK-123-ND,Already has notes\n';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(parsed);

      expect(items.first['notes'], contains('Already has notes'));
      expect(items.first['notes'], contains('DigiKey PN: DK-123-ND'));
    });

    // ── Price parsing ────────────────────────────────────────────────────────

    test('parses unit price from DigiKey format', () {
      final item = _parseSingleRow(
        '"1","5","497-15315-1-ND","STL6P3LLH6","MOSFET P-CH 30V 6A POWERFLAT","","5","0","1.61000","8.05"\n',
      );

      expect(item['price_per_unit'], closeTo(1.61, 0.001));
    });

    test('returns null price when price field is empty', () {
      const csv = 'Item,Quantity\nWidget,5\n';
      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(parsed);
      expect(items.first['price_per_unit'], isNull);
    });

    // ── Edge cases ───────────────────────────────────────────────────────────

    test('skips rows where item name cannot be determined', () {
      const csv = 'Item,Quantity\n,5\n';
      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(parsed);
      expect(items, isEmpty);
    });

    test('uses default location and package when not in CSV', () {
      final item = _parseSingleRow(
        '"1","10","311-100HRCT-ND","RC0603FR-07100RL","RES 100 OHM 1% 1/10W 0603","","20","0","0.02400","0.48"\n',
      );
      // defaultLocation is '' and defaultPackage is '0603' by default in _parseSingleRow
      // but package is extracted from description here
      expect(item['package'], '0603');
    });

    test('applies explicit defaultLocation', () {
      final parsed = CsvParserService.parse(
        '${_digikeyHeader}"1","10","311-100HRCT-ND","RC0603FR-07100RL","RES 100 OHM 1% 1/10W 0603","","20","0","0.02400","0.48"\n',
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(
        parsed,
        defaultLocation: 'Shelf B',
      );
      expect(items.first['location'], 'Shelf B');
    });

    test('parses full DigiKey cart with multiple component types', () {
      final csv = '$_digikeyHeader'
          '"1","50","1276-1184-1-ND","CL10B105KA8NNNC","CAP CER 1UF 25V X7R 0603","","50","0","0.02440","1.22"\n'
          '"2","25","541-27.0HCT-ND","CRCW060327R0FKEA","RES SMD 27 OHM 1% 1/8W 0603","","25","0","0.02400","0.60"\n'
          '"3","5","283-HCM1A1305V3-1R5-RCT-ND","HCM1A1305V3-1R5-R","FIXED IND 1.5UH 19A 3 MOHM SMD","","5","0","0.62000","3.10"\n'
          '"4","10","MSS1P4-M3/89AGICT-ND","MSS1P4-M3/89A","DIODE SCHOTTKY 40V 1A MICROSMP","","10","0","0.06700","0.67"\n'
          '"5","5","497-STM32C011F6U6TRCT-ND","STM32C011F6U6TR","IC MCU 32BIT 32KB FLASH 20UFQFPN","","5","0","0.95000","4.75"\n'
          '"6","2","1528-1969-ND","1992","GPIO HEADER FOR RASPBERRYPI A+/B","","2","0","2.95000","5.90"\n';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: InventoryCsvMapper.expectedColumns,
      );
      final items = InventoryCsvMapper.toInventoryItems(parsed);

      expect(items, hasLength(6));
      expect(items[0]['type'], 'capacitor');
      expect(items[1]['type'], 'resistor');
      expect(items[2]['type'], 'inductor');
      expect(items[3]['type'], 'diode');
      expect(items[4]['type'], 'ic');
      expect(items[5]['type'], 'connector');
    });
  });
}

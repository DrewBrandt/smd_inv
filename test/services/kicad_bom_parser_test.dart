import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/services/csv_parser_service.dart';
import 'package:smd_inv/services/kicad_bom_parser.dart';

void main() {
  group('KicadBomParser', () {
    test('parses core KiCad columns and skips DNP/mechanical rows', () {
      const csv =
          '''"Reference","Value","Footprint","Qty","DNP","Exclude from BOM"
"C1","100nF","Capacitor_SMD:C_0603_1608Metric","1","",""
"R1","10k","Resistor_SMD:R_0603_1608Metric","2","",""
"H1","MountingHole","MountingHole:MountingHole_3.2mm_M3","1","","Excluded from BOM"
"U1","BMI088","BMI088:PQFN50P450X300X100-16N","1","",""''';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: KicadBomParser.expectedColumns,
      );
      final result = KicadBomParser.parse(parsed);

      expect(result.success, true);
      expect(result.lines.length, 3);
      expect(result.skippedRows, 1);
    });

    test('normalizes passive package and value for matching', () {
      const csv = '''Reference,Qty,Value,Footprint
C1,1,100nF,Capacitor_SMD:C_0603_1608Metric''';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: KicadBomParser.expectedColumns,
      );
      final result = KicadBomParser.parse(parsed);

      final attrs =
          result.lines.first[FirestoreFields.requiredAttributes]
              as Map<String, dynamic>;
      expect(attrs['part_type'], 'capacitor');
      expect(attrs[FirestoreFields.value], '100n');
      expect(attrs['size'], '0603');
    });

    test('detects connector/ic from reference and preserves likely MPN', () {
      const csv = '''Reference,Qty,Value,Footprint
J1,1,B2B-XH-A,Connector_JST:JST_XH_B2B-XH-A_1x02_P2.50mm_Vertical
U2,1,MS5611-01BA,Package_LGA:LGA-8_3x5mm_P1.25mm''';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: KicadBomParser.expectedColumns,
      );
      final result = KicadBomParser.parse(parsed);

      final j1 =
          result.lines.first[FirestoreFields.requiredAttributes]
              as Map<String, dynamic>;
      final u2 =
          result.lines.last[FirestoreFields.requiredAttributes]
              as Map<String, dynamic>;

      expect(j1['part_type'], 'connector');
      expect(j1[FirestoreFields.partNumber], 'B2B-XH-A');
      expect(u2['part_type'], 'ic');
      expect(u2[FirestoreFields.partNumber], 'MS5611-01BA');
    });

    test('supports alternate KiCad column order', () {
      const csv =
          '''"Reference","Qty","Value","DNP","Exclude from BOM","Footprint"
"R1,R2","2","5k1","","","Resistor_SMD:R_0603_1608Metric"
"U1","1","BMI088","","","BMI088:PQFN50P450X300X100-16N"''';

      final parsed = CsvParserService.parse(
        csv,
        expectedColumns: KicadBomParser.expectedColumns,
      );
      final result = KicadBomParser.parse(parsed);

      expect(result.success, true);
      expect(result.lines.length, 2);
      expect(result.lines.first['designators'], 'R1,R2');
    });
  });
}

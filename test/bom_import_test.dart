// test/bom_import_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/csv_parser_service.dart';

// Shared helper functions
String detectPartType(String ref) {
  // Passives (including diodes and LEDs)
  // Check LED before L to avoid matching LED as inductor
  if (ref.startsWith('LED')) return 'led';
  if (ref.startsWith('C')) return 'capacitor';
  if (ref.startsWith('R')) return 'resistor';
  if (ref.startsWith('L')) return 'inductor';
  if (ref.startsWith('D')) return 'diode';

  // Connectors
  if (ref.startsWith('J') || ref.startsWith('P') || ref.startsWith('X') || ref.startsWith('CON')) return 'connector';

  // Everything else is an IC (U, Q, BZ, etc.)
  return 'ic';
}

String normalizeValue(String? raw) {
  if (raw == null) return '';
  var s = raw.trim();

  // Unify µ → u, remove spaces
  s = s.replaceAll('µ', 'u').replaceAll(RegExp(r'\s+'), '');

  // Handle nF → n notation (use replaceAllMapped to avoid $ issues)
  s = s.replaceAllMapped(RegExp(r'(\d+\.?\d*)nF', caseSensitive: false), (m) => '${m.group(1)}n');
  s = s.replaceAllMapped(RegExp(r'(\d+\.?\d*)uF', caseSensitive: false), (m) => '${m.group(1)}u');
  s = s.replaceAllMapped(RegExp(r'(\d+\.?\d*)pF', caseSensitive: false), (m) => '${m.group(1)}p');

  // Drop trailing unit markers like 'uf', 'nf', 'pf' → keep just u/n/p
  s = s.replaceAll(RegExp(r'([unpkmM])f$', caseSensitive: false), r'$1');

  // "Embedded unit as decimal separator" forms:
  //  e.g., 2u2 → 2.2u, 100n0 → 100n
  // BUT keep resistance k notation as-is (e.g., 5k1, 78k7)
  final m = RegExp(r'^(\d+)([unpkmMG])(\d+)$').firstMatch(s);
  if (m != null) {
    final intPart = m.group(1)!;
    final unit = m.group(2)!.toLowerCase();
    final frac = m.group(3)!;

    // For resistors with 'k' notation, keep as-is (e.g., 5k1 stays 5k1)
    if (unit == 'k') {
      return s; // Keep original format for resistors
    }

    // For capacitors/inductors, convert to decimal (e.g., 2u2 → 2.2u)
    if (RegExp(r'^0+$').hasMatch(frac)) {
      return '$intPart$unit'; // e.g., 100n0 → 100n
    } else {
      return '$intPart.$frac$unit'; // e.g., 2u2 → 2.2u
    }
  }

  return s;
}

void main() {
  group('BOM Import Tests', () {
    test('Parse BOM_TEST_1.csv', () async {
      final file = File('BOM_TEST_1.csv');
      expect(file.existsSync(), true, reason: 'BOM_TEST_1.csv should exist');

      final content = await file.readAsString();
      print('BOM_TEST_1.csv content length: ${content.length}');
      print('First 500 chars:\n${content.substring(0, content.length > 500 ? 500 : content.length)}');

      final result = CsvParserService.parse(
        content,
        expectedColumns: ['Reference', 'Designator', 'Quantity', 'Qty', 'Value', 'Designation', 'Footprint'],
      );

      print('\nParse success: ${result.success}');
      if (!result.success) {
        print('Error: ${result.error}');
      }
      print('Headers: ${result.headers}');
      print('Data rows: ${result.dataRows.length}');

      expect(result.success, true);
      expect(result.dataRows.isNotEmpty, true);

      // Print first few rows
      for (var i = 0; i < (result.dataRows.length > 5 ? 5 : result.dataRows.length); i++) {
        print('\nRow $i:');
        for (var header in result.headers) {
          print('  $header: ${result.getCellValue(result.dataRows[i], header)}');
        }
      }
    });

    test('Parse BOM_TEST_2.csv', () async {
      final file = File('BOM_TEST_2.csv');
      expect(file.existsSync(), true, reason: 'BOM_TEST_2.csv should exist');

      final content = await file.readAsString();
      print('BOM_TEST_2.csv content length: ${content.length}');
      print('First 500 chars:\n${content.substring(0, content.length > 500 ? 500 : content.length)}');

      final result = CsvParserService.parse(
        content,
        expectedColumns: ['Reference', 'Designator', 'Quantity', 'Qty', 'Value', 'Designation', 'Footprint'],
      );

      print('\nParse success: ${result.success}');
      if (!result.success) {
        print('Error: ${result.error}');
      }
      print('Headers: ${result.headers}');
      print('Data rows: ${result.dataRows.length}');

      expect(result.success, true);
      expect(result.dataRows.isNotEmpty, true);

      // Print first few rows
      for (var i = 0; i < (result.dataRows.length > 5 ? 5 : result.dataRows.length); i++) {
        print('\nRow $i:');
        for (var header in result.headers) {
          print('  $header: ${result.getCellValue(result.dataRows[i], header)}');
        }
      }
    });

    test('Test part type detection', () {
      expect(detectPartType('C1'), 'capacitor');
      expect(detectPartType('R1'), 'resistor');
      expect(detectPartType('L1'), 'inductor');
      expect(detectPartType('D1'), 'diode');
      expect(detectPartType('LED1'), 'led');
      expect(detectPartType('J1'), 'connector');
      expect(detectPartType('U1'), 'ic');
      expect(detectPartType('BZ1'), 'ic');
      expect(detectPartType('Q1'), 'ic');

      print('Part type detection tests passed!');
    });

    test('Test value normalization', () {
      expect(normalizeValue('100nF'), '100n');
      expect(normalizeValue('470n'), '470n');
      expect(normalizeValue('10uF'), '10u');
      expect(normalizeValue('2u2'), '2.2u');
      expect(normalizeValue('100n0'), '100n');
      expect(normalizeValue('5k1'), '5k1');
      expect(normalizeValue('78k7'), '78k7');
      expect(normalizeValue('422k'), '422k');

      print('Value normalization tests passed!');
      print('  100nF → ${normalizeValue('100nF')}');
      print('  470n → ${normalizeValue('470n')}');
      print('  10uF → ${normalizeValue('10u')}');
      print('  2u2 → ${normalizeValue('2u2')}');
      print('  5k1 → ${normalizeValue('5k1')}');
    });

    test('Test package extraction', () {
      String extractPackage(String ref, String footprint) {
        final partType = detectPartType(ref);

        if (['capacitor', 'resistor', 'inductor', 'diode', 'led'].contains(partType)) {
          // For passives: extract size (0603, 0805, etc.)
          final sizeMatch = RegExp(r'(0201|0402|0603|0805|1206|1210|2512|1005|1608|2012|2520|3216|3225)').firstMatch(footprint);
          if (sizeMatch != null) {
            final extracted = sizeMatch.group(0)!;
            final imperialSizes = {
              '1005': '0402',
              '1608': '0603',
              '2012': '0805',
              '3216': '1206',
              '2520': '1008',
              '3225': '1210',
            };
            return imperialSizes[extracted] ?? extracted;
          }
        } else {
          // For ICs/connectors: extract package type (BGA, QFN, etc.)
          final packagePatterns = [
            RegExp(r'\b(BGA|TFBGA|FBGA)\b', caseSensitive: false),
            RegExp(r'\b(QFN|VQFN|HVQFN|DHVQFN|PQFN)\b', caseSensitive: false),
            RegExp(r'\b(DFN)\b', caseSensitive: false),
            RegExp(r'\b(LQFP|QFP|TQFP)\b', caseSensitive: false),
            RegExp(r'\b(SOIC|SO|SOP)\b', caseSensitive: false),
            RegExp(r'\b(SOT-\d+)\b', caseSensitive: false),
            RegExp(r'\b(TSOP|TSSOP|SSOP)\b', caseSensitive: false),
            RegExp(r'\b(LGA)\b', caseSensitive: false),
            RegExp(r'\b(WLCSP|WLP)\b', caseSensitive: false),
            RegExp(r'\b(PSON)\b', caseSensitive: false),
          ];

          for (final pattern in packagePatterns) {
            final match = pattern.firstMatch(footprint);
            if (match != null) {
              return match.group(0)!.toUpperCase();
            }
          }
        }
        return '';
      }

      // Test passive packages
      expect(extractPackage('C1', 'Capacitor_SMD:C_0603_1608Metric'), '0603');
      expect(extractPackage('R1', 'Resistor_SMD:R_0805_2012Metric'), '0805');

      // Test IC packages
      expect(extractPackage('U1', 'Package_BGA:TFBGA-100_8x8mm_Layout10x10_P0.8mm'), 'TFBGA');
      expect(extractPackage('U2', 'Package_DFN_QFN:DHVQFN-14-1EP_2.5x3mm_P0.5mm_EP1x1.5mm'), 'DHVQFN');
      expect(extractPackage('U3', 'Package_TO_SOT_SMD:SOT-563'), 'SOT-563');
      expect(extractPackage('U4', 'Package_BGA:WLP-4_0.86x0.86mm_P0.4mm'), 'WLP');

      print('Package extraction tests passed!');
    });
  });
}

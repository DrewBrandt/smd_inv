import '../constants/firestore_constants.dart';
import 'csv_parser_service.dart';
import 'part_normalizer.dart';

class KicadBomParser {
  static const expectedColumns = <String>[
    'Reference',
    'References',
    'Designator',
    'Quantity',
    'Qty',
    'Value',
    'Designation',
    'Footprint',
    'DNP',
    'Exclude from BOM',
    'Exclude from Board',
  ];

  static KicadBomParseResult parse(CsvParseResult parseResult) {
    final parsed = <Map<String, dynamic>>[];
    int skipped = 0;

    final refCol = _firstPresentColumn(parseResult, const [
      'Reference',
      'References',
      'Designator',
    ]);
    final qtyCol = _firstPresentColumn(parseResult, const ['Quantity', 'Qty']);
    final valueCol = _firstPresentColumn(parseResult, const [
      'Value',
      'Designation',
    ]);
    final footprintCol = _firstPresentColumn(parseResult, const ['Footprint']);

    if (refCol == null || qtyCol == null) {
      return const KicadBomParseResult(
        lines: [],
        skippedRows: 0,
        error:
            'Could not find required columns: Reference/Designator and Quantity/Qty.',
      );
    }

    for (final row in parseResult.dataRows) {
      final designators = parseResult.getCellValue(row, refCol).trim();
      if (designators.isEmpty) {
        skipped++;
        continue;
      }

      final valueRaw =
          valueCol == null ? '' : parseResult.getCellValue(row, valueCol);
      final footprint =
          footprintCol == null
              ? ''
              : parseResult.getCellValue(row, footprintCol);
      final qtyRaw = parseResult.getCellValue(row, qtyCol);
      final qty = int.tryParse(qtyRaw) ?? 1;

      final dnp = parseResult.getCellValue(row, 'DNP');
      final excludeFromBom = parseResult.getCellValue(row, 'Exclude from BOM');
      final excludeFromBoard = parseResult.getCellValue(
        row,
        'Exclude from Board',
      );

      if (_shouldSkipRow(
        designators: designators,
        valueRaw: valueRaw,
        footprint: footprint,
        dnp: dnp,
        excludeFromBom: excludeFromBom,
        excludeFromBoard: excludeFromBoard,
      )) {
        skipped++;
        continue;
      }

      final firstRef = _firstDesignator(designators);
      final partType = _detectPartType(firstRef, valueRaw: valueRaw);
      final category = _detectCategory(partType);
      final packageInfo = _extractPackage(
        partType: partType,
        footprint: footprint,
      );
      final normalizedValue = PartNormalizer.normalizeValue(valueRaw);
      final inferredPartNumber = _extractLikelyPartNumber(
        valueRaw: valueRaw,
        partType: partType,
      );

      parsed.add({
        'designators': designators,
        FirestoreFields.qty: qty <= 0 ? 1 : qty,
        FirestoreFields.notes: '',
        FirestoreFields.description: _describeFromFootprint(footprint),
        FirestoreFields.category: category,
        FirestoreFields.requiredAttributes: {
          'part_type': partType,
          FirestoreFields.value: normalizedValue,
          'size': packageInfo,
          FirestoreFields.partNumber: inferredPartNumber,
          FirestoreFields.selectedComponentRef: null,
        },
        '_original_value': valueRaw,
        '_original_footprint': footprint,
        '_match_status': 'pending',
        '_ignored': false,
      });
    }

    return KicadBomParseResult(lines: parsed, skippedRows: skipped);
  }

  static String? _firstPresentColumn(
    CsvParseResult result,
    List<String> aliases,
  ) {
    for (final alias in aliases) {
      if (result.hasColumn(alias)) {
        return alias;
      }
      final hasHeader = result.headers.any((h) {
        final hl = h.toLowerCase().trim();
        final al = alias.toLowerCase().trim();
        return hl == al || hl.contains(al) || al.contains(hl);
      });
      if (hasHeader) {
        return alias;
      }
    }
    return null;
  }

  static bool _shouldSkipRow({
    required String designators,
    required String valueRaw,
    required String footprint,
    required String dnp,
    required String excludeFromBom,
    required String excludeFromBoard,
  }) {
    if (_isTruthy(dnp) ||
        _isTruthy(excludeFromBom) ||
        _isTruthy(excludeFromBoard)) {
      return true;
    }
    if (valueRaw.trim().toUpperCase() == 'DNP') return true;

    // Common KiCad mechanical exclusions.
    if (designators.toUpperCase().startsWith('H') &&
        footprint.toLowerCase().contains('mountinghole')) {
      return true;
    }

    return false;
  }

  static bool _isTruthy(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == '1' ||
        s == 'true' ||
        s == 'yes' ||
        s == 'y' ||
        s == 'x' ||
        s == 'excluded' ||
        s == 'dnp' ||
        s == 'do not populate' ||
        s == 'do not place';
  }

  static String _firstDesignator(String designators) {
    return designators.split(',').first.trim().toUpperCase();
  }

  static String _detectPartType(String ref, {required String valueRaw}) {
    if (ref.startsWith('LED')) return 'led';
    if (ref.startsWith('C')) return 'capacitor';
    if (ref.startsWith('R')) return 'resistor';
    if (ref.startsWith('L')) return 'inductor';
    if (ref.startsWith('D')) return 'diode';
    if (ref.startsWith('J') ||
        ref.startsWith('P') ||
        ref.startsWith('X') ||
        ref.startsWith('CON')) {
      return 'connector';
    }
    if (ref.startsWith('Y') || ref.startsWith('XTAL')) return 'crystal';

    final value = valueRaw.trim().toLowerCase();
    if (value.contains('connector') || value.contains('jst')) {
      return 'connector';
    }
    return 'ic';
  }

  static String _detectCategory(String partType) {
    if (PartNormalizer.isPassive(partType)) return 'components';
    if (partType == 'connector') return 'connectors';
    return 'ics';
  }

  static String _extractPackage({
    required String partType,
    required String footprint,
  }) {
    final upper = footprint.toUpperCase();

    final passiveSize = RegExp(
      r'(0201|0402|0603|0805|1206|1210|2512|1005|1608|2012|2520|3216|3225)',
    ).firstMatch(upper);
    if (passiveSize != null && PartNormalizer.isPassive(partType)) {
      return PartNormalizer.normalizePackage(
        passiveSize.group(1)!,
      ).toUpperCase();
    }

    final commonPackage = RegExp(
      r'\b(BGA|TFBGA|FBGA|QFN|VQFN|HVQFN|DFN|PQFN|LQFP|QFP|TQFP|SOIC|SO|SOP|TSOP|TSSOP|SSOP|LGA|WLCSP|WLP|PSON|SOT-\d+|DIP-\d+)\b',
    ).firstMatch(upper);
    if (commonPackage != null) return commonPackage.group(1)!.toUpperCase();

    final diodePackage = RegExp(
      r'\b(SOD-\d+|SMA|SMB|SMC|DO-214AA|DO-214AB|DO-214AC)\b',
    ).firstMatch(upper);
    if (diodePackage != null) return diodePackage.group(1)!.toUpperCase();

    return '';
  }

  static String _extractLikelyPartNumber({
    required String valueRaw,
    required String partType,
  }) {
    if (PartNormalizer.isPassive(partType) || partType == 'crystal') {
      return '';
    }

    final value = valueRaw.trim();
    if (value.isEmpty) return '';
    final normalized = value.toLowerCase();
    const labels = {
      'gps',
      'sens',
      'pwr',
      'sw',
      'uart',
      'i2c',
      'usb',
      'sma',
      'pyro',
      'bat',
      'buzzer',
      'mountinghole',
      '~',
    };
    if (labels.contains(normalized)) return '';

    final hasLetters = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasDigits = RegExp(r'\d').hasMatch(value);
    if ((hasLetters && hasDigits && value.length >= 5) || value.contains('-')) {
      return value;
    }
    return '';
  }

  static String _describeFromFootprint(String footprint) {
    if (footprint.trim().isEmpty) return '';
    return footprint.split(':').last.split('_').join(' ').trim();
  }
}

class KicadBomParseResult {
  final List<Map<String, dynamic>> lines;
  final int skippedRows;
  final String? error;

  const KicadBomParseResult({
    required this.lines,
    required this.skippedRows,
    this.error,
  });

  bool get success => error == null;
}

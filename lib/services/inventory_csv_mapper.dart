import '../constants/firestore_constants.dart';
import 'digikey_part_resolver.dart';
import 'csv_parser_service.dart';

/// Maps parsed inventory CSV rows into Firestore inventory documents.
class InventoryCsvMapper {
  static const expectedColumns = <String>[
    'Item',
    'Description',
    'Quantity',
    'Link',
    'Notes',
    'Price Per Unit',
    'Unit Price',
    'Part Number',
    'DigiKey Part Number',
    'Digi-Key Part Number',
    'DigiKey PN',
    'Manufacturer Part Number',
  ];

  static List<Map<String, dynamic>> toInventoryItems(
    CsvParseResult parseResult, {
    String defaultLocation = '',
    String defaultPackage = '0603',
  }) {
    final items = <Map<String, dynamic>>[];

    for (final row in parseResult.dataRows) {
      final item = parseRow(
        parseResult,
        row,
        defaultLocation: defaultLocation,
        defaultPackage: defaultPackage,
      );
      if (item != null) items.add(item);
    }

    return items;
  }

  static Map<String, dynamic>? parseRow(
    CsvParseResult parseResult,
    List<dynamic> row, {
    String defaultLocation = '',
    String defaultPackage = '0603',
  }) {
    final itemName = _firstNonEmpty(parseResult, row, const [
      'Item',
      'Description',
      'Manufacturer Part Number',
      'Part Number',
    ]);
    if (itemName.isEmpty) return null;

    final qty =
        int.tryParse(_firstNonEmpty(parseResult, row, const ['Quantity'])) ?? 0;
    final rawLink = _firstNonEmpty(parseResult, row, const ['Link']);
    final notes = _firstNonEmpty(parseResult, row, const ['Notes']);
    final priceStr = _firstNonEmpty(parseResult, row, const [
      'Price Per Unit',
      'Unit Price',
    ]);
    final digiKeyPartNumber = _firstNonEmpty(parseResult, row, const [
      'DigiKey Part Number',
      'Digi-Key Part Number',
      'DigiKey PN',
      'Part Number',
    ]);
    final manufacturerPartNumber = _firstNonEmpty(parseResult, row, const [
      'Manufacturer Part Number',
    ]);

    final link =
        rawLink.isNotEmpty
            ? rawLink
            : _buildDigiKeySearchUrl(digiKeyPartNumber);
    final extractedLinkPartNumber = _extractPartNumberFromDigiKeyLink(rawLink);
    final partNumber =
        manufacturerPartNumber.isNotEmpty
            ? manufacturerPartNumber
            : extractedLinkPartNumber.isNotEmpty
            ? extractedLinkPartNumber
            : digiKeyPartNumber;
    final pricePerUnit = _parsePrice(priceStr);

    final item = _buildInventoryItem(
      itemName: itemName,
      qty: qty,
      partNumber: partNumber,
      link: link,
      notes: _buildNotes(notes, digiKeyPartNumber: digiKeyPartNumber),
      pricePerUnit: pricePerUnit,
      defaultLocation: defaultLocation,
      defaultPackage: defaultPackage,
      hasDirectProductLink: rawLink.isNotEmpty,
    );
    final normalizedDigiKeyPartNumber =
        DigiKeyPartResolver.normalize(digiKeyPartNumber) ?? digiKeyPartNumber;
    if (normalizedDigiKeyPartNumber.isNotEmpty) {
      item[FirestoreFields.digiKeyPartNumber] = normalizedDigiKeyPartNumber;
    }
    return item;
  }

  static String _firstNonEmpty(
    CsvParseResult parseResult,
    List<dynamic> row,
    List<String> columnNames,
  ) {
    for (final columnName in columnNames) {
      final value = parseResult.getCellValue(row, columnName);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static double? _parsePrice(String priceStr) {
    if (priceStr.isEmpty) return null;
    final cleaned = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  static String _buildNotes(String notes, {required String digiKeyPartNumber}) {
    if (digiKeyPartNumber.isEmpty) return notes;
    final digiKeyNote = 'DigiKey PN: $digiKeyPartNumber';
    if (notes.isEmpty) return digiKeyNote;
    if (notes.contains(digiKeyNote)) return notes;
    return '$notes | $digiKeyNote';
  }

  static String _extractPartNumberFromDigiKeyLink(String link) {
    if (!link.contains('digikey.com')) return '';
    final match = RegExp(r'/detail/[^/]+/([^/]+)/').firstMatch(link);
    return match?.group(1) ?? '';
  }

  static String _buildDigiKeySearchUrl(String digiKeyPartNumber) {
    if (digiKeyPartNumber.isEmpty) return '';
    return 'https://www.digikey.com/en/products/result?keywords='
        '${Uri.encodeQueryComponent(digiKeyPartNumber)}';
  }

  static Map<String, dynamic> _buildInventoryItem({
    required String itemName,
    required int qty,
    required String partNumber,
    required String link,
    required String notes,
    required double? pricePerUnit,
    required String defaultLocation,
    required String defaultPackage,
    required bool hasDirectProductLink,
  }) {
    final itemLower = itemName.toLowerCase();
    final extractedPackage = _extractPackage(itemName) ?? '';

    if (_looksLikeCapacitor(itemLower)) {
      final value = _extractValue(itemName);
      return {
        FirestoreFields.partNumber:
            partNumber.isNotEmpty
                ? partNumber
                : 'CAP-$defaultPackage-${value ?? "UNKNOWN"}',
        FirestoreFields.type: 'capacitor',
        FirestoreFields.value: value,
        FirestoreFields.package:
            extractedPackage.isNotEmpty ? extractedPackage : defaultPackage,
        FirestoreFields.description: itemName,
        FirestoreFields.qty: qty,
        FirestoreFields.location: defaultLocation,
        FirestoreFields.notes: notes,
        FirestoreFields.vendorLink: link,
        FirestoreFields.pricePerUnit: pricePerUnit,
        FirestoreFields.datasheet: hasDirectProductLink ? link : null,
      };
    }

    // Inductors checked before resistors: DigiKey descriptions often include
    // DCR specs like "3 MOHM" which would otherwise trigger the resistor check.
    if (_looksLikeInductor(itemLower)) {
      return {
        FirestoreFields.partNumber:
            partNumber.isNotEmpty ? partNumber : itemName,
        FirestoreFields.type: 'inductor',
        FirestoreFields.value: _extractValue(itemName),
        FirestoreFields.package:
            extractedPackage.isNotEmpty ? extractedPackage : defaultPackage,
        FirestoreFields.description: itemName,
        FirestoreFields.qty: qty,
        FirestoreFields.location: defaultLocation,
        FirestoreFields.notes: notes,
        FirestoreFields.vendorLink: link,
        FirestoreFields.pricePerUnit: pricePerUnit,
        FirestoreFields.datasheet: hasDirectProductLink ? link : null,
      };
    }

    if (_looksLikeResistor(itemLower)) {
      final value = _extractValue(itemName);
      return {
        FirestoreFields.partNumber:
            partNumber.isNotEmpty
                ? partNumber
                : 'RES-$defaultPackage-${value ?? "UNKNOWN"}',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: value,
        FirestoreFields.package:
            extractedPackage.isNotEmpty ? extractedPackage : defaultPackage,
        FirestoreFields.description: itemName,
        FirestoreFields.qty: qty,
        FirestoreFields.location: defaultLocation,
        FirestoreFields.notes: notes,
        FirestoreFields.vendorLink: link,
        FirestoreFields.pricePerUnit: pricePerUnit,
        FirestoreFields.datasheet: hasDirectProductLink ? link : null,
      };
    }

    if (_looksLikeConnector(itemLower)) {
      return {
        FirestoreFields.partNumber:
            partNumber.isNotEmpty ? partNumber : itemName,
        FirestoreFields.type: 'connector',
        FirestoreFields.value: null,
        FirestoreFields.package: extractedPackage,
        FirestoreFields.description: itemName,
        FirestoreFields.qty: qty,
        FirestoreFields.location: defaultLocation,
        FirestoreFields.notes: notes,
        FirestoreFields.vendorLink: link,
        FirestoreFields.pricePerUnit: pricePerUnit,
        FirestoreFields.datasheet: hasDirectProductLink ? link : null,
      };
    }

    if (_looksLikeDiode(itemLower)) {
      return {
        FirestoreFields.partNumber:
            partNumber.isNotEmpty ? partNumber : itemName,
        FirestoreFields.type: 'diode',
        FirestoreFields.value: null,
        FirestoreFields.package: extractedPackage,
        FirestoreFields.description: itemName,
        FirestoreFields.qty: qty,
        FirestoreFields.location: defaultLocation,
        FirestoreFields.notes: notes,
        FirestoreFields.vendorLink: link,
        FirestoreFields.pricePerUnit: pricePerUnit,
        FirestoreFields.datasheet: hasDirectProductLink ? link : null,
      };
    }

    return {
      FirestoreFields.partNumber: partNumber.isNotEmpty ? partNumber : itemName,
      FirestoreFields.type: 'ic',
      FirestoreFields.value: null,
      FirestoreFields.package: extractedPackage,
      FirestoreFields.description: itemName,
      FirestoreFields.qty: qty,
      FirestoreFields.location: defaultLocation,
      FirestoreFields.notes: notes,
      FirestoreFields.vendorLink: link,
      FirestoreFields.pricePerUnit: pricePerUnit,
      FirestoreFields.datasheet: hasDirectProductLink ? link : null,
    };
  }

  static bool _looksLikeCapacitor(String itemLower) {
    return itemLower.contains('cap ') ||
        itemLower.startsWith('cap') ||
        itemLower.contains('capacitor') ||
        // Match "10uf", "0.047uf", "470pf", "100nf" but NOT "20ufqfpn" (no word boundary)
        RegExp(r'\d\s*(uf|pf|nf)\b').hasMatch(itemLower);
  }

  static bool _looksLikeResistor(String itemLower) {
    return itemLower.contains('res ') ||
        itemLower.startsWith('res') ||
        itemLower.contains('resistor') ||
        itemLower.contains('ohm');
  }

  static bool _looksLikeInductor(String itemLower) {
    return itemLower.contains('fixed ind') || itemLower.contains('inductor');
  }

  static bool _looksLikeConnector(String itemLower) {
    return itemLower.contains('connector') ||
        itemLower.contains('conn ') ||
        itemLower.contains('header') ||
        itemLower.contains('receptacle') ||
        itemLower.contains('pin male') ||
        itemLower.contains('pin female') ||
        itemLower.contains('jst');
  }

  static bool _looksLikeDiode(String itemLower) {
    return itemLower.contains('diode');
  }

  static String? _extractValue(String itemName) {
    final match = RegExp(
      r'(\d+\.?\d*)\s*(u|n|p|k|m|M|G)?(?:F|H|ohm)?',
      caseSensitive: false,
    ).firstMatch(itemName);

    if (match == null) return null;

    final num = match.group(1);
    final unit = match.group(2)?.toLowerCase() ?? '';
    if (unit.isEmpty) return num;
    return '$num$unit';
  }

  static String? _extractPackage(String itemName) {
    final patterns = [
      RegExp(
        r'\b(0201|0402|0603|0805|1206|1210|2512|1005|1608|2012|2520|3216|3225)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(SOIC|QFP|QFN|DIP|TSSOP|VFQFPN|UFQFPN|LQFP|TQFP|DFN|SON|LGA|WLP|BGA|SMA|SMB|SMC|MICROSMP|POWERFLAT|PPAK1212)-?\d*\b',
        caseSensitive: false,
      ),
      RegExp(r'\bSOT[- ]?\d+(?:-\d+)?\b', caseSensitive: false),
      RegExp(r'\bJST[- ]?[A-Z]{2}[- ]?\d+P?\b', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(itemName);
      if (match != null) return match.group(0);
    }

    return null;
  }
}

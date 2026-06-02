import 'package:csv/csv.dart';

import '../models/procurement.dart';
import 'digikey_part_resolver.dart';

class CartPasteParser {
  static List<ManualProcurementLine> parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const <ManualProcurementLine>[];

    final csvLines = _parseCsvLike(trimmed);
    final csvResult = _parseRows(csvLines);
    if (csvResult.isNotEmpty) return csvResult;

    return _parseLooseLines(trimmed);
  }

  static List<List<dynamic>> _parseCsvLike(String text) {
    try {
      return const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
    } catch (_) {
      return const <List<dynamic>>[];
    }
  }

  static List<ManualProcurementLine> _parseRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const <ManualProcurementLine>[];

    final headers = rows.first.map((cell) => '$cell'.trim()).toList();
    final headerIndex = _buildHeaderIndex(headers);
    if (!_looksLikeHeader(headerIndex)) return const <ManualProcurementLine>[];

    final qtyIndex = _findHeader(headerIndex, const [
      'quantity',
      'qty',
      'order qty',
      'purchase qty',
    ]);
    final explicitDigiKeyIndex = _findHeader(headerIndex, const [
      'digikey part number',
      'digi-key part number',
      'digikey pn',
      'digikey part #',
      'digi-key part #',
    ]);
    final manufacturerIndex = _findHeader(headerIndex, const [
      'manufacturer part number',
      'manufacturer pn',
      'mpn',
      'part_#',
      'part #',
    ]);
    final plainPartNumberIndex = _findHeader(headerIndex, const [
      'part number',
    ]);
    final digiKeyIndex =
        explicitDigiKeyIndex ??
        (manufacturerIndex != null ? plainPartNumberIndex : null);
    final mpnIndex =
        manufacturerIndex ??
        (digiKeyIndex == null ? plainPartNumberIndex : null);
    final descriptionIndex = _findHeader(headerIndex, const [
      'description',
      'item',
      'notes',
    ]);
    final linkIndex = _findHeader(headerIndex, const [
      'vendor link',
      'link',
      'url',
    ]);

    if (qtyIndex == null || (digiKeyIndex == null && mpnIndex == null)) {
      return const <ManualProcurementLine>[];
    }

    final lines = <ManualProcurementLine>[];
    for (final row in rows.skip(1)) {
      final quantity = _parseQuantity(_cell(row, qtyIndex));
      if (quantity <= 0) continue;

      final rawDigiKey = _cell(row, digiKeyIndex);
      final digiKeyPn = DigiKeyPartResolver.normalize(rawDigiKey);
      final mpn = _cell(row, mpnIndex);
      final partNumber = mpn.isNotEmpty ? mpn : (digiKeyPn ?? rawDigiKey);
      if (partNumber.trim().isEmpty && digiKeyPn == null) continue;

      final description = _cell(row, descriptionIndex);
      final vendorLink = _cell(row, linkIndex);
      lines.add(
        ManualProcurementLine(
          partNumber: partNumber.trim(),
          digikeyPartNumber: digiKeyPn,
          description: description.isNotEmpty ? description : partNumber.trim(),
          quantity: quantity,
          vendorLink: vendorLink.isEmpty ? null : vendorLink,
          boardLabel: 'Pasted cart',
        ),
      );
    }
    return lines;
  }

  static List<ManualProcurementLine> _parseLooseLines(String text) {
    final lines = <ManualProcurementLine>[];
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      var parts =
          line
              .split(RegExp(r'[\t,;]|\s{2,}'))
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toList();
      if (parts.length < 2) {
        final leadingQty = RegExp(r'^(\d+)\s+(.+)$').firstMatch(line);
        final trailingQty = RegExp(r'^(.+?)\s+(\d+)$').firstMatch(line);
        if (leadingQty != null) {
          parts = [leadingQty.group(1)!, leadingQty.group(2)!];
        } else if (trailingQty != null) {
          parts = [trailingQty.group(1)!, trailingQty.group(2)!];
        }
      }
      if (parts.length < 2) continue;

      final firstQty = _parseQuantity(parts.first);
      final lastQty = _parseQuantity(parts.last);
      final quantity = firstQty > 0 ? firstQty : lastQty;
      if (quantity <= 0) continue;

      final identifier =
          firstQty > 0
              ? parts.skip(1).join(' ')
              : parts.take(parts.length - 1).join(' ');
      if (identifier.trim().isEmpty) continue;

      final digiKeyPn = DigiKeyPartResolver.normalize(identifier);
      lines.add(
        ManualProcurementLine(
          partNumber: identifier.trim(),
          digikeyPartNumber: digiKeyPn,
          description: identifier.trim(),
          quantity: quantity,
          boardLabel: 'Pasted cart',
        ),
      );
    }
    return lines;
  }

  static Map<String, int> _buildHeaderIndex(List<String> headers) {
    return {
      for (var i = 0; i < headers.length; i++) _normalizeHeader(headers[i]): i,
    };
  }

  static bool _looksLikeHeader(Map<String, int> index) {
    return index.containsKey('quantity') ||
        index.containsKey('qty') ||
        index.containsKey('digikey part number') ||
        index.containsKey('manufacturer part number');
  }

  static int? _findHeader(Map<String, int> index, List<String> aliases) {
    for (final alias in aliases) {
      final value = index[_normalizeHeader(alias)];
      if (value != null) return value;
    }
    return null;
  }

  static String _cell(List<dynamic> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return '${row[index]}'.trim();
  }

  static int _parseQuantity(String raw) {
    if (raw.trim().isEmpty) return 0;
    final cleaned = raw.trim();
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) return 0;
    return int.tryParse(cleaned) ?? 0;
  }

  static String _normalizeHeader(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

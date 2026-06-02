import '../constants/firestore_constants.dart';

class DigiKeyPartResolver {
  static String? resolveFromInventoryData(
    Map<String, dynamic> data, {
    String? fallbackPartNumber,
  }) {
    return normalize(data[FirestoreFields.digiKeyPartNumber]?.toString()) ??
        extractDigiKeyPartNumber(
          data[FirestoreFields.vendorLink]?.toString(),
          fallbackPartNumber: fallbackPartNumber,
        ) ??
        extractDigiKeyPartNumber(data[FirestoreFields.datasheet]?.toString()) ??
        extractFromNotes(data[FirestoreFields.notes]?.toString()) ??
        normalize(fallbackPartNumber);
  }

  static String? resolveFromBomAttributes(
    Map<String, dynamic> attrs, {
    String? fallbackPartNumber,
  }) {
    return normalize(attrs[FirestoreFields.digiKeyPartNumber]?.toString()) ??
        extractDigiKeyPartNumber(
          attrs[FirestoreFields.vendorLink]?.toString(),
          fallbackPartNumber: fallbackPartNumber,
        ) ??
        extractFromNotes(attrs[FirestoreFields.notes]?.toString()) ??
        normalize(fallbackPartNumber);
  }

  static String? extractDigiKeyPartNumber(
    String? vendorLink, {
    String? fallbackPartNumber,
  }) {
    final fallback = normalize(fallbackPartNumber);
    if (vendorLink == null || vendorLink.trim().isEmpty) {
      return fallback;
    }

    final uri = Uri.tryParse(vendorLink.trim());
    if (uri == null) return fallback;

    final host = uri.host.toLowerCase();
    if (!host.contains('digikey')) return fallback;

    for (final segment in uri.pathSegments.reversed) {
      final value = normalize(segment);
      if (value != null) return value;
    }

    for (final key in ['item', 'part', 'partnumber', 'pn', 'keywords']) {
      final value = normalize(uri.queryParameters[key]);
      if (value != null) return value;
    }

    return fallback;
  }

  static String? extractFromNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;

    final labeledMatch = RegExp(
      r'(?:Digi-?Key\s*(?:PN|Part\s*#|Part\s*Number)\s*:\s*)([A-Za-z0-9./-]+-ND)\b',
      caseSensitive: false,
    ).firstMatch(notes);
    final labeled = normalize(labeledMatch?.group(1));
    if (labeled != null) return labeled;

    final genericMatch = RegExp(
      r'\b([A-Za-z0-9./-]+-ND)\b',
      caseSensitive: false,
    ).firstMatch(notes);
    return normalize(genericMatch?.group(1));
  }

  static String? normalize(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9./-]+-ND$', caseSensitive: false).hasMatch(value)) {
      return value.toUpperCase();
    }
    return null;
  }

  static String searchUrl(String query) {
    return 'https://www.digikey.com/en/products/result?keywords='
        '${Uri.encodeQueryComponent(query.trim())}';
  }
}

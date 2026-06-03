/// Normalized DigiKey product data returned by the `digikeyLookup` Cloud
/// Function. Mirrors the payload the function writes to inventory docs /
/// `digikey_cache` documents.
class DigiKeyPartInfo {
  final String? digiKeyPartNumber;
  final String? manufacturerPartNumber;
  final String? description;
  final double? unitPrice;
  final String? productUrl;
  final String? datasheetUrl;
  final String? packageCase;
  final int? quantityAvailable;

  /// True when DigiKey returned no match for the requested identifier. The
  /// function caches these so unknown parts aren't re-queried every 24h.
  final bool notFound;

  const DigiKeyPartInfo({
    this.digiKeyPartNumber,
    this.manufacturerPartNumber,
    this.description,
    this.unitPrice,
    this.productUrl,
    this.datasheetUrl,
    this.packageCase,
    this.quantityAvailable,
    this.notFound = false,
  });

  bool get hasData => !notFound;

  factory DigiKeyPartInfo.fromJson(Map<String, dynamic> json) {
    return DigiKeyPartInfo(
      digiKeyPartNumber: _str(json['digiKeyPartNumber']),
      manufacturerPartNumber: _str(json['manufacturerPartNumber']),
      description: _str(json['description']),
      unitPrice: _toDouble(json['unitPrice']),
      productUrl: _str(json['productUrl']),
      datasheetUrl: _str(json['datasheetUrl']),
      packageCase: _str(json['packageCase']),
      quantityAvailable: _toInt(json['quantityAvailable']),
      notFound: json['notFound'] == true,
    );
  }

  static String? _str(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// A single part to resolve via DigiKey. [key] is the stable cache identifier
/// (the line's preferred order identifier); [inventoryDocId] is supplied when
/// the part is backed by an inventory document so the function refreshes that
/// doc instead of the `digikey_cache` collection.
class DigiKeyLookupRequest {
  final String key;
  final String? dkPn;
  final String? mpn;
  final String? inventoryDocId;

  const DigiKeyLookupRequest({
    required this.key,
    this.dkPn,
    this.mpn,
    this.inventoryDocId,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    if (dkPn != null && dkPn!.isNotEmpty) 'dkPn': dkPn,
    if (mpn != null && mpn!.isNotEmpty) 'mpn': mpn,
    if (inventoryDocId != null && inventoryDocId!.isNotEmpty)
      'inventoryDocId': inventoryDocId,
  };
}

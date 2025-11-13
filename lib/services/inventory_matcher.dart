import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for matching BOM lines to inventory items
///
/// Provides consistent matching logic across readiness calculation,
/// BOM import, and board production workflows.
class InventoryMatcher {
  /// Find matching inventory items for BOM line attributes
  ///
  /// Strategy priority:
  /// 1. Exact match by selected_component_ref (if provided)
  /// 2. For ICs/connectors: match by part number (using value field from BOM)
  /// 3. For passives (R/L/C/D/LED): match by type + value + package
  ///
  /// Returns list of matching documents (empty if no match)
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> findMatches({
    required Map<String, dynamic> bomAttributes,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;

    // Fetch inventory if not provided
    final inventory = inventorySnapshot ??
        await db.collection('inventory').get();

    // Strategy 1: Match by selected_component_ref
    final selectedRef = bomAttributes['selected_component_ref']?.toString();
    if (selectedRef != null && selectedRef.isNotEmpty) {
      try {
        // First check if it's already in the inventory snapshot
        final match = inventory.docs.where((doc) => doc.id == selectedRef).toList();
        if (match.isNotEmpty) {
          return match;
        }

        // Fallback: try fetching from Firestore (for cases where snapshot not provided)
        final doc = await db
            .collection('inventory')
            .doc(selectedRef)
            .get();
        if (doc.exists) {
          return [doc as QueryDocumentSnapshot<Map<String, dynamic>>];
        }
      } catch (_) {
        // Invalid ref, continue to other strategies
      }
    }

    // Strategy 2: Match by value (for ICs/connectors, value IS the part number)
    final partType = bomAttributes['part_type']?.toString().toLowerCase() ?? '';
    final value = bomAttributes['value']?.toString() ?? '';
    final size = bomAttributes['size']?.toString() ?? '';

    // For non-passives, match by part number using the value field
    if (value.isNotEmpty && !_isPassive(partType)) {
      final matches = inventory.docs.where((doc) {
        final data = doc.data();
        return data['part_#']?.toString().trim().toLowerCase() ==
            value.trim().toLowerCase();
      }).toList();

      if (matches.isNotEmpty) return matches;
    }

    // Strategy 3: Match passives by type + value + package

    if (_isPassive(partType) && value.isNotEmpty && size.isNotEmpty) {
      final matches = inventory.docs.where((doc) {
        final data = doc.data();
        return data['type']?.toString().toLowerCase() == partType &&
            data['value']?.toString().trim() == value.trim() &&
            data['package']?.toString().trim().toLowerCase() ==
                size.trim().toLowerCase();
      }).toList();

      if (matches.isNotEmpty) return matches;
    }

    // No matches found
    return [];
  }

  /// Find single best match for BOM line
  ///
  /// Returns null if no match or multiple ambiguous matches
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findBestMatch({
    required Map<String, dynamic> bomAttributes,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
    FirebaseFirestore? firestore,
  }) async {
    final matches = await findMatches(
      bomAttributes: bomAttributes,
      inventorySnapshot: inventorySnapshot,
      firestore: firestore,
    );

    return matches.length == 1 ? matches.first : null;
  }

  /// Check if part type is a passive component (R/L/C/D/LED)
  static bool _isPassive(String partType) {
    final type = partType.toLowerCase();
    return type == 'capacitor' ||
        type == 'resistor' ||
        type == 'inductor' ||
        type == 'diode' ||
        type == 'led';
  }

  /// Get match result with metadata
  static Future<InventoryMatchResult> getMatchResult({
    required Map<String, dynamic> bomAttributes,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
    FirebaseFirestore? firestore,
  }) async {
    final matches = await findMatches(
      bomAttributes: bomAttributes,
      inventorySnapshot: inventorySnapshot,
      firestore: firestore,
    );

    if (matches.isEmpty) {
      return InventoryMatchResult.notFound();
    } else if (matches.length == 1) {
      return InventoryMatchResult.exactMatch(matches.first);
    } else {
      return InventoryMatchResult.multipleMatches(matches);
    }
  }

  /// Create human-readable label for BOM line
  static String makePartLabel(Map<String, dynamic> attrs) {
    final parts = <String>[];

    final partType = attrs['part_type']?.toString() ?? '';
    final value = attrs['value']?.toString() ?? '';
    final size = attrs['size']?.toString() ?? '';

    if (partType.isNotEmpty) parts.add(partType);
    if (value.isNotEmpty) parts.add(value);
    if (size.isNotEmpty) parts.add(size);

    return parts.isEmpty ? 'Unknown part' : parts.join(' ');
  }
}

/// Result of inventory matching operation
class InventoryMatchResult {
  final MatchType type;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> matches;

  InventoryMatchResult._(this.type, this.matches);

  factory InventoryMatchResult.notFound() {
    return InventoryMatchResult._(MatchType.notFound, []);
  }

  factory InventoryMatchResult.exactMatch(
      QueryDocumentSnapshot<Map<String, dynamic>> match) {
    return InventoryMatchResult._(MatchType.exactMatch, [match]);
  }

  factory InventoryMatchResult.multipleMatches(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> matches) {
    return InventoryMatchResult._(MatchType.multipleMatches, matches);
  }

  bool get hasMatch => matches.isNotEmpty;
  bool get isExact => type == MatchType.exactMatch;
  bool get isAmbiguous => type == MatchType.multipleMatches;
  bool get notFound => type == MatchType.notFound;

  QueryDocumentSnapshot<Map<String, dynamic>>? get singleMatch =>
      isExact ? matches.first : null;
}

enum MatchType {
  notFound,
  exactMatch,
  multipleMatches,
}

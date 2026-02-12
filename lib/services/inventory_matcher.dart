import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';
import 'part_normalizer.dart';

/// Service for matching BOM lines to inventory items
///
/// Provides consistent matching logic across readiness calculation,
/// BOM import, and board production workflows.
class InventoryMatcher {
  /// Find matching inventory items for BOM line attributes
  ///
  /// Strategy priority:
  /// 1. Exact match by selected_component_ref (if provided)
  /// 2. Exact part number (`part_#`) match
  /// 3. For ICs/connectors: match by part number using BOM value field
  /// 4. For passives (R/L/C/D/LED): match by type + value + package
  ///
  /// Returns list of matching documents (empty if no match)
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> findMatches({
    required Map<String, dynamic> bomAttributes,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore;

    // Fetch inventory if not provided (requires firestore client)
    final inventory =
        inventorySnapshot ??
        await _requireDb(db).collection(FirestoreCollections.inventory).get();

    // Strategy 1: Match by selected_component_ref
    final selectedRef = _readString(
      bomAttributes,
      FirestoreFields.selectedComponentRef,
    );
    if (selectedRef != null && selectedRef.isNotEmpty) {
      try {
        // First check if it's already in the inventory snapshot
        final match =
            inventory.docs.where((doc) => doc.id == selectedRef).toList();
        if (match.isNotEmpty) {
          return match;
        }

        // Fallback: try fetching from Firestore (for cases where snapshot not provided)
        if (db != null) {
          final doc =
              await db
                  .collection(FirestoreCollections.inventory)
                  .doc(selectedRef)
                  .get();
          if (doc.exists) {
            return [doc as QueryDocumentSnapshot<Map<String, dynamic>>];
          }
        }
      } catch (_) {
        // Invalid ref, continue to other strategies
      }
    }

    // Strategy 2: Exact part number (preferred deterministic identity)
    final partNumber = _readString(bomAttributes, FirestoreFields.partNumber);
    if (partNumber != null && partNumber.isNotEmpty) {
      final matches =
          inventory.docs.where((doc) {
            final data = doc.data();
            return _partNumberEq(data[FirestoreFields.partNumber], partNumber);
          }).toList();

      if (matches.isNotEmpty) return matches;
    }

    // Strategy 3: For non-passives, many KiCad BOMs put MPN in `value`.
    final partType = PartNormalizer.normalizePartType(
      _readString(bomAttributes, 'part_type') ?? '',
    );
    final value = _readString(bomAttributes, FirestoreFields.value) ?? '';
    final size = _readString(bomAttributes, 'size') ?? '';

    if (value.isNotEmpty && !PartNormalizer.isPassive(partType)) {
      final matches =
          inventory.docs.where((doc) {
            final data = doc.data();
            return _partNumberEq(data[FirestoreFields.partNumber], value);
          }).toList();

      if (matches.isNotEmpty) return matches;
    }

    // Strategy 4: Match passives by type + value + package (strict).
    if (PartNormalizer.isPassive(partType) && value.isNotEmpty) {
      final wantedPackage = PartNormalizer.canonicalPackage(size);
      final strictMatches =
          inventory.docs.where((doc) {
            final data = doc.data();
            final invType = PartNormalizer.normalizePartType(
              data[FirestoreFields.type]?.toString() ?? '',
            );
            if (invType != partType) return false;

            final invValue = data[FirestoreFields.value]?.toString() ?? '';
            final valueEqual = PartNormalizer.valuesLikelyEqual(
              a: value,
              b: invValue,
              partType: partType,
            );
            if (!valueEqual) return false;

            if (wantedPackage.isEmpty) return true;
            final invPackage = PartNormalizer.canonicalPackage(
              data[FirestoreFields.package]?.toString() ?? '',
            );
            return invPackage == wantedPackage;
          }).toList();

      if (strictMatches.isNotEmpty) return strictMatches;

      // Fallback: if package data is incomplete, auto-resolve only if unique.
      final relaxed =
          inventory.docs.where((doc) {
            final data = doc.data();
            final invType = PartNormalizer.normalizePartType(
              data[FirestoreFields.type]?.toString() ?? '',
            );
            if (invType != partType) return false;
            return PartNormalizer.valuesLikelyEqual(
              a: value,
              b: data[FirestoreFields.value]?.toString() ?? '',
              partType: partType,
            );
          }).toList();
      if (relaxed.length == 1) return relaxed;
      if (relaxed.isNotEmpty && size.isEmpty) return relaxed;
    }

    // Strategy 5: weighted fallback for partial data.
    final weighted = _weightedCandidates(
      inventory: inventory.docs,
      bomPartType: partType,
      bomValue: value,
      bomSize: size,
      bomPartNumber: partNumber ?? '',
    );
    if (weighted.isNotEmpty) return weighted;

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
    final partNumber = _readString(attrs, FirestoreFields.partNumber);
    if (partNumber != null && partNumber.isNotEmpty) return partNumber;

    final parts = <String>[];

    final partType = _readString(attrs, 'part_type') ?? '';
    final value = _readString(attrs, FirestoreFields.value) ?? '';
    final size = _readString(attrs, 'size') ?? '';

    if (partType.isNotEmpty) parts.add(partType);
    if (value.isNotEmpty) parts.add(value);
    if (size.isNotEmpty) parts.add(size);

    return parts.isEmpty ? 'Unknown part' : parts.join(' ');
  }

  static bool _partNumberEq(dynamic a, String b) {
    final av = PartNormalizer.canonicalPartNumber(a?.toString() ?? '');
    final bv = PartNormalizer.canonicalPartNumber(b);
    if (av.isEmpty || bv.isEmpty) return false;
    return av == bv;
  }

  static String? _readString(Map<String, dynamic> attrs, String key) {
    final raw = attrs[key];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _weightedCandidates({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> inventory,
    required String bomPartType,
    required String bomValue,
    required String bomSize,
    required String bomPartNumber,
  }) {
    final desiredPackage = PartNormalizer.canonicalPackage(bomSize);
    final desiredPart = PartNormalizer.canonicalPartNumber(
      bomPartNumber.isNotEmpty ? bomPartNumber : bomValue,
    );

    final scored =
        <({QueryDocumentSnapshot<Map<String, dynamic>> doc, int score})>[];

    for (final doc in inventory) {
      final data = doc.data();
      final invType = PartNormalizer.normalizePartType(
        data[FirestoreFields.type]?.toString() ?? '',
      );
      final invValue = data[FirestoreFields.value]?.toString() ?? '';
      final invPackage = PartNormalizer.canonicalPackage(
        data[FirestoreFields.package]?.toString() ?? '',
      );
      final invPart = PartNormalizer.canonicalPartNumber(
        data[FirestoreFields.partNumber]?.toString() ?? '',
      );

      int score = 0;

      if (bomPartType.isNotEmpty && invType == bomPartType) score += 3;
      if (bomValue.isNotEmpty &&
          PartNormalizer.valuesLikelyEqual(
            a: bomValue,
            b: invValue,
            partType: bomPartType.isNotEmpty ? bomPartType : invType,
          )) {
        score += 4;
      }
      if (desiredPackage.isNotEmpty &&
          invPackage.isNotEmpty &&
          desiredPackage == invPackage) {
        score += 3;
      }
      if (desiredPart.isNotEmpty && invPart.isNotEmpty) {
        if (desiredPart == invPart) {
          score += 8;
        } else if (invPart.contains(desiredPart) ||
            desiredPart.contains(invPart)) {
          score += 5;
        }
      }

      if (score >= 7) {
        scored.add((doc: doc, score: score));
      }
    }

    if (scored.isEmpty) return const [];

    final best = scored.map((s) => s.score).reduce((a, b) => a > b ? a : b);
    return scored.where((s) => s.score == best).map((s) => s.doc).toList();
  }

  static FirebaseFirestore _requireDb(FirebaseFirestore? db) {
    if (db != null) return db;
    return FirebaseFirestore.instance;
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
    QueryDocumentSnapshot<Map<String, dynamic>> match,
  ) {
    return InventoryMatchResult._(MatchType.exactMatch, [match]);
  }

  factory InventoryMatchResult.multipleMatches(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> matches,
  ) {
    return InventoryMatchResult._(MatchType.multipleMatches, matches);
  }

  bool get hasMatch => matches.isNotEmpty;
  bool get isExact => type == MatchType.exactMatch;
  bool get isAmbiguous => type == MatchType.multipleMatches;
  bool get notFound => type == MatchType.notFound;

  QueryDocumentSnapshot<Map<String, dynamic>>? get singleMatch =>
      isExact ? matches.first : null;
}

enum MatchType { notFound, exactMatch, multipleMatches }

import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';
import 'part_normalizer.dart';

typedef InventoryDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Service for matching BOM lines to inventory items
///
/// Provides consistent matching logic across readiness calculation,
/// BOM import, and board production workflows.
class InventoryMatcher {
  static List<InventoryDoc> findMatchesSync({
    required Map<String, dynamic> bomAttributes,
    required InventoryMatcherIndex matcherIndex,
  }) {
    // Strategy 1: Match by selected_component_ref
    final selectedRef = _readString(
      bomAttributes,
      FirestoreFields.selectedComponentRef,
    );
    if (selectedRef != null && selectedRef.isNotEmpty) {
      final match = matcherIndex.docById(selectedRef);
      if (match != null) return [match];
    }

    // Strategy 2: Exact part number (preferred deterministic identity)
    final partNumber = _readString(bomAttributes, FirestoreFields.partNumber);
    if (partNumber != null && partNumber.isNotEmpty) {
      final matches = matcherIndex.docsByPartNumber(partNumber);
      if (matches.isNotEmpty) return matches;
    }

    final partType = PartNormalizer.normalizePartType(
      _readString(bomAttributes, 'part_type') ?? '',
    );
    final value = _readString(bomAttributes, FirestoreFields.value) ?? '';
    final size = _readString(bomAttributes, 'size') ?? '';

    // Strategy 3: For non-passives, many KiCad BOMs put MPN in `value`.
    if (value.isNotEmpty && !PartNormalizer.isPassive(partType)) {
      final matches = matcherIndex.docsByPartNumber(value);
      if (matches.isNotEmpty) return matches;
    }

    // Strategy 4: Match passives by type + value + package (strict).
    if (PartNormalizer.isPassive(partType) && value.isNotEmpty) {
      final wantedPackage = PartNormalizer.canonicalPackage(size);
      final strictPool =
          wantedPackage.isEmpty
              ? matcherIndex.docsByPartType(partType)
              : matcherIndex.docsByPartTypeAndPackage(partType, wantedPackage);

      final strictMatches =
          strictPool.where((doc) {
            final data = doc.data();
            final invValue = data[FirestoreFields.value]?.toString() ?? '';
            return PartNormalizer.valuesLikelyEqual(
              a: value,
              b: invValue,
              partType: partType,
            );
          }).toList();

      if (strictMatches.isNotEmpty) return strictMatches;

      // Fallback: if package data is incomplete, auto-resolve only if unique.
      final relaxed =
          matcherIndex.docsByPartType(partType).where((doc) {
            final data = doc.data();
            return PartNormalizer.valuesLikelyEqual(
              a: value,
              b: data[FirestoreFields.value]?.toString() ?? '',
              partType: partType,
            );
          }).toList();
      if (relaxed.length == 1) return relaxed;
      if (relaxed.isNotEmpty && size.isEmpty) return relaxed;
    }

    // Strategy 4b: LEDs carry no value (colour is deliberately left open and
    // chosen at build time), so match on type + package and offer every
    // same-size candidate. This surfaces as an ambiguous set for the user to
    // pick from rather than "missing". Other passives with a blank value are a
    // data gap, not a wildcard, so they are intentionally excluded here.
    if (partType == 'led' && value.isEmpty) {
      final wantedPackage = PartNormalizer.canonicalPackage(size);
      if (wantedPackage.isNotEmpty) {
        final pool = matcherIndex.docsByPartTypeAndPackage(
          partType,
          wantedPackage,
        );
        if (pool.isNotEmpty) return pool;
      }
    }

    // Strategy 5: weighted fallback for partial data.
    final weighted = _weightedCandidates(
      inventory:
          partType.isEmpty
              ? matcherIndex.docs
              : matcherIndex.docsByPartType(partType),
      bomPartType: partType,
      bomValue: value,
      bomSize: size,
      bomPartNumber: partNumber ?? '',
    );
    if (weighted.isNotEmpty) return weighted;

    return const [];
  }

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
    InventoryMatcherIndex? matcherIndex,
  }) async {
    final db = firestore;

    // Fetch inventory if not provided (requires firestore client)
    final inventory =
        inventorySnapshot ??
        await _requireDb(db).collection(FirestoreCollections.inventory).get();
    final index = matcherIndex ?? InventoryMatcherIndex.fromSnapshot(inventory);

    final matches = findMatchesSync(
      bomAttributes: bomAttributes,
      matcherIndex: index,
    );
    if (matches.isNotEmpty || db == null) {
      return matches;
    }

    final selectedRef = _readString(
      bomAttributes,
      FirestoreFields.selectedComponentRef,
    );
    if (selectedRef != null && selectedRef.isNotEmpty) {
      final query =
          await db
              .collection(FirestoreCollections.inventory)
              .where(FieldPath.documentId, isEqualTo: selectedRef)
              .limit(1)
              .get();
      if (query.docs.isNotEmpty) {
        return query.docs;
      }
    }

    return [];
  }

  /// Find single best match for BOM line
  ///
  /// Returns null if no match or multiple ambiguous matches
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findBestMatch({
    required Map<String, dynamic> bomAttributes,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
    FirebaseFirestore? firestore,
    InventoryMatcherIndex? matcherIndex,
  }) async {
    final matches = await findMatches(
      bomAttributes: bomAttributes,
      inventorySnapshot: inventorySnapshot,
      firestore: firestore,
      matcherIndex: matcherIndex,
    );

    return matches.length == 1 ? matches.first : null;
  }

  /// Get match result with metadata
  static Future<InventoryMatchResult> getMatchResult({
    required Map<String, dynamic> bomAttributes,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
    FirebaseFirestore? firestore,
    InventoryMatcherIndex? matcherIndex,
  }) async {
    final matches = await findMatches(
      bomAttributes: bomAttributes,
      inventorySnapshot: inventorySnapshot,
      firestore: firestore,
      matcherIndex: matcherIndex,
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
    required List<InventoryDoc> inventory,
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

class InventoryMatcherIndex {
  final QuerySnapshot<Map<String, dynamic>> inventorySnapshot;
  final Map<String, InventoryDoc> _docsById;
  final Map<String, List<InventoryDoc>> _docsByCanonicalPartNumber;
  final Map<String, List<InventoryDoc>> _docsByPartType;
  final Map<String, List<InventoryDoc>> _docsByPartTypeAndPackage;

  InventoryMatcherIndex._({
    required this.inventorySnapshot,
    required Map<String, InventoryDoc> docsById,
    required Map<String, List<InventoryDoc>> docsByCanonicalPartNumber,
    required Map<String, List<InventoryDoc>> docsByPartType,
    required Map<String, List<InventoryDoc>> docsByPartTypeAndPackage,
  }) : _docsById = docsById,
       _docsByCanonicalPartNumber = docsByCanonicalPartNumber,
       _docsByPartType = docsByPartType,
       _docsByPartTypeAndPackage = docsByPartTypeAndPackage;

  factory InventoryMatcherIndex.fromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final docsById = <String, InventoryDoc>{};
    final docsByCanonicalPartNumber = <String, List<InventoryDoc>>{};
    final docsByPartType = <String, List<InventoryDoc>>{};
    final docsByPartTypeAndPackage = <String, List<InventoryDoc>>{};

    for (final doc in snapshot.docs) {
      docsById[doc.id] = doc;
      final data = doc.data();

      final canonicalPartNumber = PartNormalizer.canonicalPartNumber(
        data[FirestoreFields.partNumber]?.toString() ?? '',
      );
      if (canonicalPartNumber.isNotEmpty) {
        docsByCanonicalPartNumber
            .putIfAbsent(canonicalPartNumber, () => <InventoryDoc>[])
            .add(doc);
      }

      final partType = PartNormalizer.normalizePartType(
        data[FirestoreFields.type]?.toString() ?? '',
      );
      if (partType.isNotEmpty) {
        docsByPartType.putIfAbsent(partType, () => <InventoryDoc>[]).add(doc);

        final package = PartNormalizer.canonicalPackage(
          data[FirestoreFields.package]?.toString() ?? '',
        );
        if (package.isNotEmpty) {
          final key = '$partType|$package';
          docsByPartTypeAndPackage
              .putIfAbsent(key, () => <InventoryDoc>[])
              .add(doc);
        }
      }
    }

    return InventoryMatcherIndex._(
      inventorySnapshot: snapshot,
      docsById: docsById,
      docsByCanonicalPartNumber: docsByCanonicalPartNumber,
      docsByPartType: docsByPartType,
      docsByPartTypeAndPackage: docsByPartTypeAndPackage,
    );
  }

  List<InventoryDoc> get docs => inventorySnapshot.docs;

  InventoryDoc? docById(String docId) => _docsById[docId];

  List<InventoryDoc> docsByPartNumber(String rawPartNumber) {
    final canonical = PartNormalizer.canonicalPartNumber(rawPartNumber);
    if (canonical.isEmpty) return const [];
    return _docsByCanonicalPartNumber[canonical] ?? const [];
  }

  List<InventoryDoc> docsByPartType(String rawPartType) {
    final type = PartNormalizer.normalizePartType(rawPartType);
    if (type.isEmpty) return const [];
    return _docsByPartType[type] ?? const [];
  }

  List<InventoryDoc> docsByPartTypeAndPackage(
    String rawPartType,
    String rawPackage,
  ) {
    final type = PartNormalizer.normalizePartType(rawPartType);
    final package = PartNormalizer.canonicalPackage(rawPackage);
    if (type.isEmpty || package.isEmpty) return const [];
    return _docsByPartTypeAndPackage['$type|$package'] ?? const [];
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

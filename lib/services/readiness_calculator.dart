// lib/services/readiness_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/board.dart';
import '../models/readiness.dart';
import '../constants/firestore_constants.dart';
import 'inventory_matcher.dart';

class ReadinessCalculator {
  static Readiness calculateSync(
    BoardDoc board, {
    required InventoryMatcherIndex matcherIndex,
  }) {
    if (board.bom.isEmpty) {
      return const Readiness(
        buildableQty: 0,
        readyPct: 0.0,
        shortfalls: [],
        totalCost: 0.0,
      );
    }

    final shortfalls = <Shortfall>[];
    final ambiguousParts = <String>[];
    double totalCost = 0.0;
    int minBuildableQty = 999999;

    final activeLines = board.bom.where((line) => !line.ignored).toList();

    if (activeLines.isEmpty) {
      return const Readiness(
        buildableQty: 0,
        readyPct: 1.0,
        shortfalls: [],
        ambiguousParts: [],
        totalCost: 0.0,
      );
    }

    for (final line in activeLines) {
      final attrs = line.requiredAttributes;
      final requiredQty = line.qty;
      final matches = InventoryMatcher.findMatchesSync(
        bomAttributes: attrs,
        matcherIndex: matcherIndex,
      );

      if (matches.isEmpty) {
        final label = InventoryMatcher.makePartLabel(attrs);
        shortfalls.add(Shortfall(label, requiredQty));
        minBuildableQty = 0;
        continue;
      }

      // The same part can live in multiple inventory entries (e.g. split
      // across locations). Total stock across every match determines whether
      // the board can be built; the user picks which entry to pull from when
      // there is more than one.
      int availableQty = 0;
      for (final match in matches) {
        availableQty += (match.data()[FirestoreFields.qty] as num?)?.toInt() ?? 0;
      }
      final pricePerUnit =
          (matches.first.data()[FirestoreFields.pricePerUnit] as num?)
              ?.toDouble();

      if (pricePerUnit != null) {
        totalCost += pricePerUnit * requiredQty;
      }

      final buildableWithThisPart = (availableQty / requiredQty).floor();

      if (buildableWithThisPart == 0) {
        final label = InventoryMatcher.makePartLabel(attrs);
        shortfalls.add(Shortfall(label, requiredQty - availableQty));
      } else if (matches.length > 1) {
        // In stock and buildable, but spread across multiple inventory
        // entries — a location has to be chosen at build time.
        ambiguousParts.add(InventoryMatcher.makePartLabel(attrs));
      }

      minBuildableQty =
          minBuildableQty < buildableWithThisPart
              ? minBuildableQty
              : buildableWithThisPart;
    }

    if (minBuildableQty == 999999) minBuildableQty = 0;

    final totalActiveLines = activeLines.length;
    final readyLines = totalActiveLines - shortfalls.length;
    final readyPct =
        totalActiveLines > 0
            ? (readyLines / totalActiveLines).clamp(0.0, 1.0)
            : 0.0;

    return Readiness(
      buildableQty: minBuildableQty,
      readyPct: readyPct,
      shortfalls: shortfalls,
      ambiguousParts: ambiguousParts,
      totalCost: totalCost,
    );
  }

  /// Calculate board readiness based on current inventory
  static Future<Readiness> calculate(
    BoardDoc board, {
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
  }) async {
    if (board.bom.isEmpty) {
      return const Readiness(
        buildableQty: 0,
        readyPct: 0.0,
        shortfalls: [],
        totalCost: 0.0,
      );
    }

    final inventory =
        inventorySnapshot ??
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.inventory)
            .get();
    return calculateSync(
      board,
      matcherIndex: InventoryMatcherIndex.fromSnapshot(inventory),
    );
  }

  static Future<Map<String, Readiness>> calculateAll(
    Iterable<BoardDoc> boards, {
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
  }) async {
    final inventory =
        inventorySnapshot ??
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.inventory)
            .get();
    final matcherIndex = InventoryMatcherIndex.fromSnapshot(inventory);
    return {
      for (final board in boards)
        board.id: calculateSync(board, matcherIndex: matcherIndex),
    };
  }
}

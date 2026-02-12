// lib/services/readiness_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/board.dart';
import '../models/readiness.dart';
import '../constants/firestore_constants.dart';
import 'inventory_matcher.dart';

class ReadinessCalculator {
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
    final shortfalls = <Shortfall>[];
    double totalCost = 0.0;
    int minBuildableQty = 999999; // Start with very high number

    // Only consider non-ignored lines
    final activeLines = board.bom.where((line) => !line.ignored).toList();

    if (activeLines.isEmpty) {
      return const Readiness(
        buildableQty: 0,
        readyPct: 1.0,
        shortfalls: [],
        totalCost: 0.0,
      );
    }

    for (final line in activeLines) {
      final attrs = line.requiredAttributes;
      final requiredQty = line.qty;

      // Find matching inventory item using unified matcher
      final matches = await InventoryMatcher.findMatches(
        bomAttributes: attrs,
        inventorySnapshot: inventory,
      );

      // Calculate availability
      if (matches.isEmpty) {
        // Part not in inventory
        final label = InventoryMatcher.makePartLabel(attrs);
        shortfalls.add(Shortfall(label, requiredQty));
        minBuildableQty = 0; // Can't build any if parts missing
      } else {
        final match = matches.first;
        final data = match.data();
        final availableQty = (data[FirestoreFields.qty] as num?)?.toInt() ?? 0;
        final pricePerUnit =
            (data[FirestoreFields.pricePerUnit] as num?)?.toDouble();

        // Add to cost
        if (pricePerUnit != null) {
          totalCost += pricePerUnit * requiredQty;
        }

        // Calculate how many boards we can build with this part
        final buildableWithThisPart = (availableQty / requiredQty).floor();

        if (buildableWithThisPart == 0) {
          // Not enough in stock
          final label = InventoryMatcher.makePartLabel(attrs);
          shortfalls.add(Shortfall(label, requiredQty - availableQty));
        }

        // Update minimum buildable quantity
        minBuildableQty =
            minBuildableQty < buildableWithThisPart
                ? minBuildableQty
                : buildableWithThisPart;
      }
    }

    // If we never found a limiting part, we can't build any
    if (minBuildableQty == 999999) minBuildableQty = 0;

    // Calculate readiness percentage (only based on active, non-ignored lines)
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
      totalCost: totalCost,
    );
  }
}

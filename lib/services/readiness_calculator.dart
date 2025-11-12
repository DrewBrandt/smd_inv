// lib/services/readiness_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/board.dart';
import '../models/readiness.dart';
import '../constants/firestore_constants.dart';
import 'inventory_matcher.dart';

class ReadinessCalculator {
  /// Calculate board readiness based on current inventory
  static Future<Readiness> calculate(BoardDoc board) async {
    if (board.bom.isEmpty) {
      return const Readiness(buildableQty: 0, readyPct: 0.0, shortfalls: [], totalCost: 0.0);
    }

    final inventory = await FirebaseFirestore.instance
        .collection(FirestoreCollections.inventory)
        .get();
    final shortfalls = <Shortfall>[];
    double totalCost = 0.0;
    int minBuildableQty = 999999; // Start with very high number

    for (final line in board.bom) {
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
        final availableQty = data[FirestoreFields.qty] as int? ?? 0;
        final pricePerUnit = data[FirestoreFields.pricePerUnit] as double?;

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
        minBuildableQty = minBuildableQty < buildableWithThisPart ? minBuildableQty : buildableWithThisPart;
      }
    }

    // If we never found a limiting part, we can't build any
    if (minBuildableQty == 999999) minBuildableQty = 0;

    // Calculate readiness percentage
    final totalLines = board.bom.length;
    final readyLines = totalLines - shortfalls.length;
    final readyPct = totalLines > 0 ? (readyLines / totalLines).clamp(0.0, 1.0) : 0.0;

    return Readiness(buildableQty: minBuildableQty, readyPct: readyPct, shortfalls: shortfalls, totalCost: totalCost);
  }
}

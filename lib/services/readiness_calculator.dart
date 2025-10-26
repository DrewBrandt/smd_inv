// lib/services/readiness_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/board.dart';
import '../models/readiness.dart';

class ReadinessCalculator {
  /// Calculate board readiness based on current inventory
  static Future<Readiness> calculate(BoardDoc board) async {
    if (board.bom.isEmpty) {
      return const Readiness(buildableQty: 0, readyPct: 0.0, shortfalls: [], totalCost: 0.0);
    }

    final inventory = await FirebaseFirestore.instance.collection('inventory').get();
    final shortfalls = <Shortfall>[];
    double totalCost = 0.0;
    int minBuildableQty = 999999; // Start with very high number

    for (final line in board.bom) {
      final attrs = line.requiredAttributes;
      final requiredQty = line.qty;

      // Find matching inventory item
      QueryDocumentSnapshot? match;

      // First try: exact match by selected_component_ref
      final selectedRef = attrs['selected_component_ref']?.toString();
      if (selectedRef != null && selectedRef.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('inventory').doc(selectedRef).get();
          if (doc.exists) {
            match = doc as QueryDocumentSnapshot;
          }
        } catch (_) {}
      }

      // Second try: match by part number
      if (match == null) {
        final partNum = attrs['part_#']?.toString() ?? '';
        if (partNum.isNotEmpty) {
          final matches =
              inventory.docs.where((doc) {
                final data = doc.data();
                return data['part_#']?.toString() == partNum;
              }).toList();

          if (matches.isNotEmpty) match = matches.first;
        }
      }

      // Third try: match passives by type + value + size
      if (match == null) {
        final partType = attrs['part_type']?.toString().toLowerCase() ?? '';
        final value = attrs['value']?.toString() ?? '';
        final size = attrs['size']?.toString() ?? '';

        if ((partType == 'capacitor' || partType == 'resistor' || partType == 'inductor') &&
            value.isNotEmpty &&
            size.isNotEmpty) {
          final matches =
              inventory.docs.where((doc) {
                final data = doc.data();
                return data['type']?.toString().toLowerCase() == partType &&
                    data['value']?.toString() == value &&
                    data['package']?.toString() == size;
              }).toList();

          if (matches.isNotEmpty) match = matches.first;
        }
      }

      // Calculate availability
      if (match == null) {
        // Part not in inventory
        final label = _makePartLabel(attrs);
        shortfalls.add(Shortfall(label, requiredQty));
        minBuildableQty = 0; // Can't build any if parts missing
      } else {
        final data = match.data() as Map<String, dynamic>;
        final availableQty = data['qty'] as int? ?? 0;
        final pricePerUnit = data['price_per_unit'] as double?;

        // Add to cost
        if (pricePerUnit != null) {
          totalCost += pricePerUnit * requiredQty;
        }

        // Calculate how many boards we can build with this part
        final buildableWithThisPart = (availableQty / requiredQty).floor();

        if (buildableWithThisPart == 0) {
          // Not enough in stock
          final label = _makePartLabel(attrs);
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

  static String _makePartLabel(Map<String, dynamic> attrs) {
    final parts = <String>[];

    if (attrs['part_#'] != null && attrs['part_#'].toString().isNotEmpty) {
      parts.add(attrs['part_#'].toString());
    } else {
      if (attrs['part_type'] != null) parts.add(attrs['part_type'].toString());
      if (attrs['value'] != null && attrs['value'].toString().isNotEmpty) {
        parts.add(attrs['value'].toString());
      }
      if (attrs['size'] != null && attrs['size'].toString().isNotEmpty) {
        parts.add(attrs['size'].toString());
      }
    }

    return parts.isEmpty ? 'Unknown part' : parts.join(' ');
  }
}

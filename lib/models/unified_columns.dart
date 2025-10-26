// lib/models/unified_columns.dart
import 'package:smd_inv/models/columns.dart';

/// Column configurations for the unified inventory collection
class UnifiedInventoryColumns {
  /// Columns for all items (kitchen sink view)
  static List<ColumnSpec> get all => [
    ColumnSpec(field: 'part_#', label: 'Part #'),
    ColumnSpec(field: 'type', label: 'Type', capitalize: true),
    ColumnSpec(field: 'value', label: 'Value'),
    ColumnSpec(field: 'package', label: 'Package'),
    ColumnSpec(field: 'description', label: 'Description'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ColumnSpec(field: 'location', label: 'Location'),
    ColumnSpec(field: 'price_per_unit', label: 'Price', kind: CellKind.decimal),
    ColumnSpec(field: 'notes', label: 'Notes'),
    ColumnSpec(field: 'vendor_link', label: 'Vendor', kind: CellKind.url),
  ];

  /// Columns for passive components (resistors, capacitors, inductors)
  static List<ColumnSpec> get passives => [
    ColumnSpec(field: 'type', label: 'Type', capitalize: true),
    ColumnSpec(field: 'value', label: 'Value'),
    ColumnSpec(field: 'package', label: 'Package'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ColumnSpec(field: 'location', label: 'Location'),
    ColumnSpec(field: 'notes', label: 'Notes'),
    ColumnSpec(field: 'part_#', label: 'Part #'),
  ];

  /// Columns for ICs
  static List<ColumnSpec> get ics => [
    ColumnSpec(field: 'part_#', label: 'Part #'),
    ColumnSpec(field: 'description', label: 'Description'),
    ColumnSpec(field: 'package', label: 'Package'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ColumnSpec(field: 'location', label: 'Location'),
    ColumnSpec(field: 'notes', label: 'Notes'),
    ColumnSpec(field: 'datasheet', label: 'Datasheet', kind: CellKind.url, maxPercentWidth: 70),
  ];

  /// Columns for connectors
  static List<ColumnSpec> get connectors => [
    ColumnSpec(field: 'part_#', label: 'Part #'),
    ColumnSpec(field: 'description', label: 'Description'),
    ColumnSpec(field: 'package', label: 'Package'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ColumnSpec(field: 'location', label: 'Location'),
    ColumnSpec(field: 'notes', label: 'Notes'),
  ];

  /// Get columns for a specific inventory type
  static List<ColumnSpec> forType(InventoryType type) {
    switch (type) {
      case InventoryType.all:
        return all;
      case InventoryType.passives:
        return passives;
      case InventoryType.ics:
        return ics;
      case InventoryType.connectors:
        return connectors;
    }
  }
}

/// Inventory filter types
enum InventoryType { all, passives, ics, connectors }

extension InventoryTypeExtension on InventoryType {
  String get label {
    switch (this) {
      case InventoryType.all:
        return 'All';
      case InventoryType.passives:
        return 'Passives';
      case InventoryType.ics:
        return 'ICs';
      case InventoryType.connectors:
        return 'Connectors';
    }
  }

  /// Firestore filter for this type
  /// Returns null for 'all' (no filter needed)
  List<String>? get firestoreTypes {
    switch (this) {
      case InventoryType.all:
        return null; // No filter
      case InventoryType.passives:
        return ['capacitor', 'resistor', 'inductor', 'passive'];
      case InventoryType.ics:
        return ['ic'];
      case InventoryType.connectors:
        return ['connector'];
    }
  }
}

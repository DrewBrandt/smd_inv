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
}

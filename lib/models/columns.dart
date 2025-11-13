// lib/models/columns.dart

enum CellKind { text, integer, decimal, url, dropdown }

/// Human-readable labels for common field names
const Map<String, String> kAttrLabel = {
  'qty': 'Qty',
  'part_type': 'Type',
  'size': 'Size',
  'value': 'Value',
  'part_#': 'Part #',
  'category': 'Category',
  'description': 'Description',
  'location': 'Location',
  'notes': 'Notes',
  'datasheet': 'Datasheet',
  'name': 'Name',
  'updatedAt': 'Last Updated',
  'createdAt': 'Created At',
};

String attrLabel(String? key) {
  if (key == null) return '';
  return kAttrLabel[key.split('.').last] ?? key;
}

class ColumnSpec {
  late String label; // UI label
  final String field; // Firestore field key
  final bool editable;
  final CellKind kind;
  final bool capitalize; // only affects display for text
  final int maxPercentWidth; // max width as % of table width

  /// For dropdown cells: function to provide dropdown options
  /// Returns list of {id, label} maps
  final Future<List<Map<String, String>>> Function(Map<String, dynamic> rowData)? dropdownOptionsProvider;

  ColumnSpec({
    required this.field,
    this.editable = true,
    this.kind = CellKind.text,
    this.capitalize = false,
    this.maxPercentWidth = 30,
    this.label = '',
    this.dropdownOptionsProvider,
  }) {
    if (label.isEmpty) {
      label = attrLabel(field);
    }
  }
}

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

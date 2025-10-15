enum CellKind { text, integer, decimal, url }

class ColumnSpec {
  final String label; // UI label
  final String field; // Firestore field key
  final bool editable;
  final CellKind kind;
  final bool capitalize; // only affects display for text
  final int maxPercentWidth; // max width as % of table width

  const ColumnSpec({
    required this.label,
    required this.field,
    this.editable = false,
    this.kind = CellKind.text,
    this.capitalize = false,
    this.maxPercentWidth = 30,
  });
}

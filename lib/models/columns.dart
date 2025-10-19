import 'package:smd_inv/ui/attribute_labels.dart';

enum CellKind { text, integer, decimal, url }

class ColumnSpec {
  late String label; // UI label
  final String field; // Firestore field key
  final bool editable;
  final CellKind kind;
  final bool capitalize; // only affects display for text
  final int maxPercentWidth; // max width as % of table width

  ColumnSpec({
    required this.field,
    this.editable = true,
    this.kind = CellKind.text,
    this.capitalize = false,
    this.maxPercentWidth = 30,
    this.label = '',
  }) {
    if (label.isEmpty) {
      label = attrLabel(field);
    }
  }
}

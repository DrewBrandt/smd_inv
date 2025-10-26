// lib/data/firebase_datagrid_source.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/models/columns.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import './base_datagrid_source.dart';
import './datagrid_helpers.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class FirestoreDataSource extends BaseDataGridSource {
  final List<Doc> _docs;

  FirestoreDataSource({required List<Doc> docs, required List<ColumnSpec> columns, required ColorScheme colorScheme})
    : _docs = docs,
      super(columns: columns, colorScheme: colorScheme);

  // --- Implementations of Abstract Methods ---

  @override
  int get rowCount => _docs.length;

  @override
  DataGridRow buildRowForIndex(int rowIndex) {
    final data = _docs[rowIndex].data();
    return DataGridRow(
      cells:
          columns.map((col) {
            final value = getNestedMapValue(data, col.field);
            String displayValue = value?.toString() ?? '';

            // Format 'type' field specially
            if (col.field == 'type' && displayValue.isNotEmpty) {
              displayValue = _formatType(displayValue);
            }

            return DataGridCell<String>(columnName: col.field, value: displayValue);
          }).toList(),
    );
  }

  @override
  Future<void> onCommitValue(int rowIndex, String path, dynamic parsedValue) async {
    final doc = _docs[rowIndex];
    // Firestore supports dot-notation for updates directly
    await doc.reference.update({path: parsedValue});
    // Keep the local cache in sync
    setNestedMapValue(doc.data(), path, parsedValue);
  }

  /// Format type field: IC stays caps, others capitalize first letter
  String _formatType(String type) {
    final lower = type.toLowerCase();
    if (lower == 'ic') return 'IC';
    return type[0].toUpperCase() + type.substring(1);
  }
}

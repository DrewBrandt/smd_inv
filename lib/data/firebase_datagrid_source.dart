// lib/data/firestore_datagrid_source.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../models/columns.dart';
import './base_datagrid_source.dart';
import './datagrid_helpers.dart'; // Import the shared helpers

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
            final value = getNestedMapValue(data, col.field); // Use helper
            return DataGridCell<String>(columnName: col.field, value: value?.toString() ?? '');
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
}

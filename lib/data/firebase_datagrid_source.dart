// lib/data/firebase_datagrid_source.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import './base_datagrid_source.dart';
import './datagrid_helpers.dart';
import '../services/inventory_history_service.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class FirestoreDataSource extends BaseDataGridSource {
  List<Doc> _docs;
  final InventoryHistoryService? historyService;

  FirestoreDataSource({
    required List<Doc> docs,
    required super.columns,
    required super.colorScheme,
    this.historyService,
  }) : _docs = docs;

  Doc docAt(int rowIndex) => _docs[rowIndex];

  /// Swaps in a new set of documents and refreshes the grid in place.
  ///
  /// Reusing the same source (instead of constructing a new one on every
  /// search keystroke) avoids rebuilding every row and lets the grid update
  /// incrementally rather than re-rendering from scratch.
  void updateDocs(List<Doc> docs) {
    _docs = docs;
    rebuildRows();
    notifyListeners();
  }

  Future<void> deleteAt(int rowIndex) async {
    if (rowIndex < 0 || rowIndex >= _docs.length) return;
    final doc = _docs[rowIndex];
    final docId = doc.id;
    final snapshot = Map<String, dynamic>.from(doc.data());

    // Write history before deleting so undo is always possible.
    if (historyService != null) {
      await historyService!.recordDelete(
        docId: docId,
        itemSnapshot: snapshot,
      );
    }

    await doc.reference.delete();

    // A live snapshot may have already swapped in a new `_docs` list (with this
    // doc gone) while we were awaiting the delete, so look it up by id rather
    // than trusting the original index — and only remove/notify if it's still
    // present, to avoid a RangeError or double removal.
    final currentIndex = _docs.indexWhere((d) => d.id == docId);
    if (currentIndex != -1) {
      _docs.removeAt(currentIndex);
      rebuildRows();
      notifyListeners();
    }
  }

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

            return DataGridCell<String>(
              columnName: col.field,
              value: displayValue,
            );
          }).toList(),
    );
  }

  @override
  Future<void> onCommitValue(
    int rowIndex,
    String path,
    dynamic parsedValue,
  ) async {
    final doc = _docs[rowIndex];
    final oldValue = getNestedMapValue(doc.data(), path);

    await doc.reference.update({path: parsedValue});
    setNestedMapValue(doc.data(), path, parsedValue);

    // Non-blocking history recording — don't let a history write failure
    // surface as an edit failure.
    historyService
        ?.recordEdit(
          docId: doc.id,
          fieldPath: path,
          oldValue: oldValue,
          newValue: parsedValue,
          itemSnapshot: Map<String, dynamic>.from(doc.data()),
        )
        .catchError((_) {});
  }

  @override
  Map<String, dynamic> getRowData(int rowIndex) {
    return _docs[rowIndex].data();
  }

  /// Format type field: IC stays caps, others capitalize first letter
  String _formatType(String type) {
    final lower = type.toLowerCase();
    if (lower == 'ic') return 'IC';
    return type[0].toUpperCase() + type.substring(1);
  }
}

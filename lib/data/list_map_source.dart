// lib/data/listmap_datagrid_source.dart

import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import './base_datagrid_source.dart';
import './datagrid_helpers.dart'; // Import the shared helpers

class ListMapDataSource extends BaseDataGridSource {
  final List<Map<String, dynamic>> _rowsData;
  final void Function(int rowIndex, String field, dynamic value) onCommit;

  ListMapDataSource({
    required List<Map<String, dynamic>> rows,
    required super.columns,
    required super.colorScheme,
    required this.onCommit,
  }) : _rowsData = rows;

  // --- Implementations of Abstract Methods ---

  @override
  int get rowCount => _rowsData.length;

  @override
  DataGridRow buildRowForIndex(int rowIndex) {
    final data = _rowsData[rowIndex];
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
    // Update the local map
    setNestedMapValue(_rowsData[rowIndex], path, parsedValue);

    // Trigger the callback to update the parent widget's state
    onCommit(rowIndex, path, parsedValue);
  }
}

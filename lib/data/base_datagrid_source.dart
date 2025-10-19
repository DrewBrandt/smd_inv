// lib/data/base_datagrid_source.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/columns.dart';

/// A base class for DataGridSources that handles all common UI,
/// editing, and helper logic, leaving data access abstract.
abstract class BaseDataGridSource extends DataGridSource {
  final List<ColumnSpec> columns;
  final ColorScheme colorScheme;
  final TextEditingController editingController = TextEditingController();
  String? newCellValue;

  List<DataGridRow> _dataGridRows = [];

  BaseDataGridSource({required this.columns, required this.colorScheme}) {
    _buildRows();
  }

  // --- Abstract methods for subclasses to implement ---

  /// The total number of rows in the data source.
  int get rowCount;

  /// Builds a single DataGridRow for the given index.
  /// Subclasses will call `getNestedValue` here.
  DataGridRow buildRowForIndex(int rowIndex);

  /// Handles the persistence of the new value.
  /// Subclasses will implement Firestore update or callback logic here.
  Future<void> onCommitValue(int rowIndex, String path, dynamic parsedValue);

  // --- Common (Shared) Logic ---

  void _buildRows() {
    _dataGridRows = List.generate(rowCount, (i) => buildRowForIndex(i));
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  // Helper from FirestoreDataSource
  Future<void> _openUrl(String raw) async {
    if (raw.isEmpty) return;
    Uri? uri;
    try {
      uri = Uri.parse(raw);
      if (!uri.hasScheme) uri = Uri.parse('https://$raw');
    } catch (_) {
      return;
    }
    if (kIsWeb) {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Common helpers from both files
  bool _isNumericKind(String field) {
    final spec = columns.firstWhere((c) => c.field == field, orElse: () => ColumnSpec(field: field));
    return spec.kind == CellKind.integer || spec.kind == CellKind.decimal;
  }

  bool _isUrlKind(String field) {
    final spec = columns.firstWhere((c) => c.field == field, orElse: () => ColumnSpec(field: field));
    final f = field.toLowerCase();
    return spec.kind == CellKind.url || f == 'datasheet' || f == 'url' || f == 'link';
  }

  // Common buildRow from FirestoreDataSource (it had the URL logic)
  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final rowIndex = _dataGridRows.indexOf(row);
    final even = rowIndex.isEven;
    final altColor = even ? colorScheme.surfaceContainer : colorScheme.surfaceContainerHighest;

    return DataGridRowAdapter(
      color: altColor,
      cells:
          row.getCells().map<Widget>((cell) {
            final field = cell.columnName;
            final text = cell.value?.toString() ?? '';
            final isUrl = _isUrlKind(field);
            final isNumeric = _isNumericKind(field);

            final label = Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
              textAlign: isNumeric ? TextAlign.right : TextAlign.left,
              style: isUrl && text.isNotEmpty ? const TextStyle(decoration: TextDecoration.underline) : null,
            );

            final content = Tooltip(
              message: text.isEmpty ? '' : text,
              waitDuration: const Duration(milliseconds: 500),
              child: Align(
                alignment: Alignment.centerLeft,
                child: isUrl && text.isNotEmpty ? InkWell(onTap: () => _openUrl(text), child: label) : label,
              ),
            );

            return Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: content);
          }).toList(),
    );
  }

  // Common canSubmitCell from both files
  @override
  Future<bool> canSubmitCell(DataGridRow row, RowColumnIndex rowColumnIndex, GridColumn column) async {
    final field = column.columnName;
    final spec = columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field, label: field, kind: CellKind.text),
    );
    final s = newCellValue ?? '';

    switch (spec.kind) {
      case CellKind.integer:
        return s.isEmpty || int.tryParse(s) != null;
      case CellKind.decimal:
        return s.isEmpty || double.tryParse(s) != null;
      case CellKind.text:
      case CellKind.url:
        return true;
    }
  }

  // Common onCellSubmit, modified to call abstract onCommitValue
  @override
  Future<void> onCellSubmit(DataGridRow dataGridRow, RowColumnIndex rowColumnIndex, GridColumn column) async {
    if (newCellValue == null) return;
    final oldValue =
        dataGridRow.getCells().firstWhere((c) => c.columnName == column.columnName).value?.toString() ?? '';

    if (newCellValue == oldValue) return;

    final int dataRowIndex = _dataGridRows.indexOf(dataGridRow);
    final field = column.columnName;
    final colSpec = columns.firstWhere((c) => c.field == field);

    dynamic parsedValue;
    switch (colSpec.kind) {
      case CellKind.integer:
        parsedValue = newCellValue!.isEmpty ? null : int.tryParse(newCellValue!);
        break;
      case CellKind.decimal:
        parsedValue = newCellValue!.isEmpty ? null : double.tryParse(newCellValue!);
        break;
      case CellKind.text:
      case CellKind.url:
        parsedValue = newCellValue;
        break;
    }

    // 1. Call abstract method to persist the change
    await onCommitValue(dataRowIndex, field, parsedValue);

    // 2. Rebuild the single row in the local cache
    _dataGridRows[dataRowIndex] = buildRowForIndex(dataRowIndex);

    // 3. Notify the grid
    notifyListeners();
  }

  @override
  Widget? buildEditWidget(
    DataGridRow dataGridRow,
    RowColumnIndex rowColumnIndex,
    GridColumn column,
    CellSubmit submitCell,
  ) {
    final field = column.columnName;
    final spec = columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field, label: field, kind: CellKind.text),
    );

    final String displayText =
        dataGridRow.getCells().firstWhere((DataGridCell c) => c.columnName == field).value?.toString() ?? '';
    newCellValue = null;

    final isInt = spec.kind == CellKind.integer;
    final isDec = spec.kind == CellKind.decimal;
    final isNumeric = isInt || isDec;

    final fmts =
        isInt
            ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
            : isDec
            ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), _SingleDotFormatter()]
            : const <TextInputFormatter>[];

    return Container(
      // Match the cell's horizontal padding
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        // color: Colors.orange,
        child: TextField(
          autofocus: true,
          controller: editingController..text = displayText,
          textAlign: isNumeric ? TextAlign.right : TextAlign.left,
          keyboardType:
              isInt
                  ? const TextInputType.numberWithOptions(signed: false, decimal: false)
                  : isDec
                  ? const TextInputType.numberWithOptions(signed: false, decimal: true)
                  : TextInputType.text,
          cursorHeight: 20,
          inputFormatters: fmts,
          style: const TextStyle(fontSize: 14),
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(vertical: 3),
            isCollapsed: true,
            border: InputBorder.none,
          ),
          onChanged: (value) => newCellValue = value,
          onSubmitted: (_) => submitCell(),
        ),
      ),
    );
  }
}

// Common _SingleDotFormatter from both files
class _SingleDotFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    final dots = '.'.allMatches(t).length;
    if (dots > 1) return oldValue;
    return newValue;
  }
}

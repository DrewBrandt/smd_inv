// lib/data/base_datagrid_source.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/columns.dart';
import '../widgets/searchable_part_picker.dart';

/// A base class for DataGridSources that handles all common UI,
/// editing, and helper logic, leaving data access abstract.
abstract class BaseDataGridSource extends DataGridSource {
  final List<ColumnSpec> columns;
  final ColorScheme colorScheme;
  final TextEditingController editingController = TextEditingController();
  String? newCellValue;

  List<DataGridRow> _dataGridRows = [];

  /// Maps a DataGridRow back to its index in [_dataGridRows] so that
  /// [buildRow] (called for every visible row on every frame) does not have
  /// to do an O(n) `indexOf` scan, which made rendering O(nÂ²).
  final Map<DataGridRow, int> _rowToIndex = {};

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

  /// Get the raw row data for a given index (for dropdown options provider)
  Map<String, dynamic> getRowData(int rowIndex);

  // --- Common (Shared) Logic ---

  void _buildRows() {
    _dataGridRows = List.generate(rowCount, (i) => buildRowForIndex(i));
    _reindexRows();
  }

  /// Rebuilds the rowâ†’index lookup. Cheap (O(n)) and only runs when the row
  /// set changes, never per-frame.
  void _reindexRows() {
    _rowToIndex.clear();
    for (var i = 0; i < _dataGridRows.length; i++) {
      // putIfAbsent mirrors `indexOf`'s first-occurrence semantics for any
      // rows that happen to compare equal.
      _rowToIndex.putIfAbsent(_dataGridRows[i], () => i);
    }
  }

  int _indexOfRow(DataGridRow row) =>
      _rowToIndex[row] ?? _dataGridRows.indexOf(row);

  /// Rebuilds all rows from the current data and refreshes the index.
  /// Subclasses call this after their backing data changes.
  void rebuildRows() => _buildRows();

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
    final spec = columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field),
    );
    return spec.kind == CellKind.integer || spec.kind == CellKind.decimal;
  }

  bool _isUrlKind(String field) {
    final spec = columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field),
    );
    final f = field.toLowerCase();
    return spec.kind == CellKind.url ||
        f == 'datasheet' ||
        f == 'url' ||
        f == 'link';
  }

  // Common buildRow from FirestoreDataSource (it had the URL logic)
  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final rowIndex = _indexOfRow(row);
    final even = rowIndex.isEven;
    final altColor =
        even
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerHighest;

    return DataGridRowAdapter(
      color: altColor,
      cells:
          row.getCells().map<Widget>((cell) {
            final field = cell.columnName;
            final text = cell.value?.toString() ?? '';
            final spec = columns.firstWhere(
              (c) => c.field == field,
              orElse: () => ColumnSpec(field: field),
            );

            // Handle checkbox column
            if (spec.kind == CellKind.checkbox) {
              return _buildCheckboxCell(rowIndex, field);
            }

            final isUrl = _isUrlKind(field);
            final isNumeric = _isNumericKind(field);

            final label = Text(
              text,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
              textAlign: isNumeric ? TextAlign.right : TextAlign.left,
              style:
                  isUrl && text.isNotEmpty
                      ? const TextStyle(decoration: TextDecoration.underline)
                      : null,
            );

            final content = Tooltip(
              message: text.isEmpty ? '' : text,
              waitDuration: const Duration(milliseconds: 500),
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    isUrl && text.isNotEmpty
                        ? InkWell(onTap: () => _openUrl(text), child: label)
                        : label,
              ),
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: content,
            );
          }).toList(),
    );
  }

  Widget _buildCheckboxCell(int rowIndex, String field) {
    final rowData = getRowData(rowIndex);
    final isChecked = rowData[field] == true;
    final isLockField = field == '_ignored';

    return Center(
      child:
          isLockField
              ? IconButton(
                tooltip: isChecked ? 'Locked' : 'Unlocked',
                icon: Icon(isChecked ? Icons.lock : Icons.lock_open, size: 18),
                onPressed: () async {
                  final nextValue = !isChecked;
                  await onCommitValue(rowIndex, field, nextValue);
                  rowData[field] = nextValue;
                  _dataGridRows[rowIndex] = buildRowForIndex(rowIndex);
                  _reindexRows();
                  notifyListeners();
                },
              )
              : Checkbox(
                value: isChecked,
                onChanged: (value) async {
                  final nextValue = value ?? false;
                  await onCommitValue(rowIndex, field, nextValue);
                  rowData[field] = nextValue;
                  _dataGridRows[rowIndex] = buildRowForIndex(rowIndex);
                  _reindexRows();
                  notifyListeners();
                },
              ),
    );
  }

  // Common canSubmitCell from both files
  @override
  Future<bool> canSubmitCell(
    DataGridRow dataGridRow,
    RowColumnIndex rowColumnIndex,
    GridColumn column,
  ) async {
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
      case CellKind.dropdown:
      case CellKind.text:
      case CellKind.url:
      case CellKind.checkbox:
        return true;
    }
  }

  // Common onCellSubmit, modified to call abstract onCommitValue
  @override
  Future<void> onCellSubmit(
    DataGridRow dataGridRow,
    RowColumnIndex rowColumnIndex,
    GridColumn column,
  ) async {
    if (newCellValue == null) return;
    final oldValue =
        dataGridRow
            .getCells()
            .firstWhere((c) => c.columnName == column.columnName)
            .value
            ?.toString() ??
        '';

    if (newCellValue == oldValue) return;

    final int dataRowIndex = _indexOfRow(dataGridRow);
    final field = column.columnName;
    final colSpec = columns.firstWhere((c) => c.field == field);

    dynamic parsedValue;
    switch (colSpec.kind) {
      case CellKind.integer:
        parsedValue =
            newCellValue!.isEmpty ? null : int.tryParse(newCellValue!);
        break;
      case CellKind.decimal:
        parsedValue =
            newCellValue!.isEmpty ? null : double.tryParse(newCellValue!);
        break;
      case CellKind.dropdown:
        final trimmed = newCellValue!.trim();
        parsedValue = trimmed.isEmpty ? null : trimmed;
        break;
      case CellKind.text:
      case CellKind.url:
        parsedValue = newCellValue;
        break;
      case CellKind.checkbox:
        return; // Checkboxes are handled separately, should not reach here
    }

    // 1. Call abstract method to persist the change
    await onCommitValue(dataRowIndex, field, parsedValue);

    // 2. Rebuild the single row in the local cache
    _dataGridRows[dataRowIndex] = buildRowForIndex(dataRowIndex);
    _reindexRows();

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
        dataGridRow
            .getCells()
            .firstWhere((DataGridCell c) => c.columnName == field)
            .value
            ?.toString() ??
        '';
    newCellValue = null;

    // Handle dropdown type
    if (spec.kind == CellKind.dropdown) {
      if (spec.dropdownOptionsProvider == null) {
        return const Text('No options provider');
      }

      final rowIndex = _indexOfRow(dataGridRow);
      final rowData = getRowData(rowIndex);

      return SearchablePartPicker(
        currentValue: displayText,
        optionsProvider: spec.dropdownOptionsProvider!,
        rowData: rowData,
        colorScheme: colorScheme,
        onChanged: (value) {
          newCellValue = value;
          submitCell();
        },
      );
    }

    // Handle text, integer, decimal, url types
    final isInt = spec.kind == CellKind.integer;
    final isDec = spec.kind == CellKind.decimal;
    final isNumeric = isInt || isDec;

    final fmts =
        isInt
            ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
            : isDec
            ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              _SingleDotFormatter(),
            ]
            : const <TextInputFormatter>[];

    return Container(
      // Match the cell's horizontal padding
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
      child: TextField(
        autofocus: true,
        controller: editingController..text = displayText,
        textAlign: isNumeric ? TextAlign.right : TextAlign.left,
        keyboardType:
            isInt
                ? const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: false,
                )
                : isDec
                ? const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: true,
                )
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
    );
  }
}

// Common _SingleDotFormatter from both files
class _SingleDotFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    final dots = '.'.allMatches(t).length;
    if (dots > 1) return oldValue;
    return newValue;
  }
}

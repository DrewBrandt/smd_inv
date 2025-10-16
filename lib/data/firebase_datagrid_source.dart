// lib/data/firestore_datagrid_source.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/columns.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class FirestoreDataSource extends DataGridSource {
  late List<Doc> _docs;
  late List<ColumnSpec> _columns;
  List<DataGridRow> _dataGridRows = [];
  final TextEditingController editingController = TextEditingController();
  String? newCellValue;

  FirestoreDataSource({required List<Doc> docs, required List<ColumnSpec> columns}) {
    _docs = docs;
    _columns = columns;
    _buildDataGridRows();
  }

  void _buildDataGridRows() {
    _dataGridRows =
        _docs.map<DataGridRow>((doc) {
          final data = doc.data();
          return DataGridRow(
            cells:
                _columns.map((col) {
                  final value = data[col.field];
                  return DataGridCell<String>(columnName: col.field, value: value?.toString() ?? '');
                }).toList(),
          );
        }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  bool _isNumericKind(String field) {
    final spec = _columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field, label: field, kind: CellKind.text),
    );
    return spec.kind == CellKind.integer || spec.kind == CellKind.decimal;
  }

  bool _isUrlKind(String field) {
    final spec = _columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field, label: field, kind: CellKind.text),
    );
    final f = field.toLowerCase();
    return spec.kind == CellKind.url || f == 'datasheet' || f == 'url' || f == 'link';
  }

  Future<void> _openUrl(String raw) async {
    if (raw.isEmpty) return;
    Uri? uri;
    try {
      uri = Uri.parse(raw);
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$raw'); // be lenient: add scheme if missing
      }
    } catch (_) {
      return;
    }
    if (kIsWeb) {
      // open new tab on web
      // ignore: use_build_context_synchronously
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final rowIndex = _dataGridRows.indexOf(row);
    final even = rowIndex.isEven;
    // Alternating row color using theme tones
    final Color? altColor = even ? null : Colors.black.withOpacity(0.03); // subtle; tweak to taste

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

  @override
  Future<bool> canSubmitCell(DataGridRow row, RowColumnIndex rowColumnIndex, GridColumn column) async{
    final field = column.columnName;
    final spec = _columns.firstWhere(
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

  @override
  Future<void> onCellSubmit(DataGridRow dataGridRow, RowColumnIndex rowColumnIndex, GridColumn column) async {
    final oldValue =
        dataGridRow.getCells().firstWhere((c) => c.columnName == column.columnName).value?.toString() ?? '';

    if ((newCellValue ?? '') == oldValue) return;

    final int dataRowIndex = _dataGridRows.indexOf(dataGridRow);
    final doc = _docs[dataRowIndex];
    final field = column.columnName;
    final colSpec = _columns.firstWhere((c) => c.field == field);

    dynamic parsedValue;
    final raw = newCellValue ?? '';

    switch (colSpec.kind) {
      case CellKind.integer:
        parsedValue = raw.isEmpty ? null : int.tryParse(raw);
        break;
      case CellKind.decimal:
        parsedValue = raw.isEmpty ? null : double.tryParse(raw);
        break;
      case CellKind.text:
      case CellKind.url:
        parsedValue = raw;
        break;
    }

    await doc.reference.update({field: parsedValue});
    doc.data()[field] = parsedValue;

    _dataGridRows[dataRowIndex] = DataGridRow(
      cells:
          _columns.map((col) {
            final value = _docs[dataRowIndex].data()[col.field];
            return DataGridCell<String>(columnName: col.field, value: value?.toString() ?? '');
          }).toList(),
    );

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
    final spec = _columns.firstWhere(
      (c) => c.field == field,
      orElse: () => ColumnSpec(field: field, label: field, kind: CellKind.text),
    );

    final String displayText =
        dataGridRow.getCells().firstWhere((DataGridCell c) => c.columnName == field).value?.toString() ?? '';

    newCellValue = null;

    final isInt = spec.kind == CellKind.integer;
    final isDec = spec.kind == CellKind.decimal;
    final isNumeric = isInt || isDec;

    final List<TextInputFormatter> fmts =
        isInt
            ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
            : isDec
            ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), _SingleDotFormatter()]
            : const <TextInputFormatter>[];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
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
        inputFormatters: fmts,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => newCellValue = value,
        onSubmitted: (_) => submitCell(),
      ),
    );
  }
}

class _SingleDotFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text;
    final dots = '.'.allMatches(t).length;
    if (dots > 1) return oldValue;
    return newValue;
  }
}

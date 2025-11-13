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

  /// Get the raw row data for a given index (for dropdown options provider)
  Map<String, dynamic> getRowData(int rowIndex);

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
      case CellKind.dropdown:
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
      case CellKind.dropdown:
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

    // Handle dropdown type
    if (spec.kind == CellKind.dropdown) {
      if (spec.dropdownOptionsProvider == null) {
        return const Text('No options provider');
      }

      final rowIndex = _dataGridRows.indexOf(dataGridRow);
      final rowData = getRowData(rowIndex);

      return _DropdownEditor(
        currentValue: displayText,
        optionsProvider: spec.dropdownOptionsProvider!,
        rowData: rowData,
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
            ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), _SingleDotFormatter()]
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

/// Searchable dropdown editor for cells with dropdown type
class _DropdownEditor extends StatefulWidget {
  final String currentValue;
  final Future<List<Map<String, String>>> Function(Map<String, dynamic> rowData) optionsProvider;
  final Map<String, dynamic> rowData;
  final ValueChanged<String?> onChanged;

  const _DropdownEditor({
    required this.currentValue,
    required this.optionsProvider,
    required this.rowData,
    required this.onChanged,
  });

  @override
  State<_DropdownEditor> createState() => _DropdownEditorState();
}

class _DropdownEditorState extends State<_DropdownEditor> {
  List<Map<String, String>>? _allOptions;
  List<Map<String, String>> _filteredOptions = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  final _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterOptions);
    _loadOptions();
  }

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await widget.optionsProvider(widget.rowData);
      if (mounted) {
        setState(() {
          _allOptions = options;
          _filteredOptions = options;
          _loading = false;
        });
        // Auto-open dropdown after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
            _showOverlay();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allOptions = [];
          _filteredOptions = [];
          _loading = false;
        });
      }
    }
  }

  void _filterOptions() {
    if (_allOptions == null) return;

    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOptions = _allOptions!;
      } else {
        _filteredOptions = _allOptions!.where((option) {
          final id = option['id']?.toLowerCase() ?? '';
          final partNum = option['part_#']?.toLowerCase() ?? '';
          final type = option['type']?.toLowerCase() ?? '';
          final value = option['value']?.toLowerCase() ?? '';
          final pkg = option['package']?.toLowerCase() ?? '';
          final location = option['location']?.toLowerCase() ?? '';

          return id.contains(query) ||
              partNum.contains(query) ||
              type.contains(query) ||
              value.contains(query) ||
              pkg.contains(query) ||
              location.contains(query);
        }).toList();
      }
    });

    // Update overlay if showing
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _showOverlay() {
    _removeOverlay();

    // Get the render box to determine width
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 300;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 30),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _filteredOptions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No matches found', style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _filteredOptions.length,
                      itemBuilder: (context, index) {
                        final option = _filteredOptions[index];
                        return _buildOptionTile(option);
                      },
                    ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOptionTile(Map<String, String> option) {
    final id = option['id'] ?? '';
    final partNum = option['part_#'] ?? '';
    final type = option['type'] ?? '';
    final value = option['value'] ?? '';
    final pkg = option['package'] ?? '';
    final qty = option['qty'] ?? '';
    final location = option['location'] ?? '';

    final isSelected = id == widget.currentValue;

    return InkWell(
      onTap: () {
        _removeOverlay();
        widget.onChanged(id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : null,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main line: part# or type+value
            Row(
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.check, size: 16, color: Colors.blue.shade700),
                  ),
                Expanded(
                  child: Text(
                    partNum.isNotEmpty ? partNum : '$type $value',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                // Stock indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStockColor(qty),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Qty: $qty',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Details line: package + location
            Row(
              children: [
                if (pkg.isNotEmpty) ...[
                  Icon(Icons.memory, size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    pkg,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  location.isEmpty ? '(no location)' : location,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStockColor(String qtyStr) {
    final qty = int.tryParse(qtyStr) ?? 0;
    if (qty == 0) return Colors.red.shade700;
    if (qty < 10) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading matches...', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    if (_allOptions == null || _allOptions!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('No inventory matches found', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search ${_allOptions!.length} matches...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => _searchController.clear(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                : const Icon(Icons.search, size: 16),
            suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          onTap: () {
            if (_overlayEntry == null) _showOverlay();
          },
          onSubmitted: (_) {
            if (_filteredOptions.length == 1) {
              widget.onChanged(_filteredOptions.first['id']);
            }
            _removeOverlay();
          },
        ),
      ),
    );
  }
}

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
    final rowIndex = _dataGridRows.indexOf(row);
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

    return Center(
      child: Checkbox(
        value: isChecked,
        onChanged: (value) async {
          final nextValue = value ?? false;
          await onCommitValue(rowIndex, field, nextValue);
          rowData[field] = nextValue;
          _dataGridRows[rowIndex] = buildRowForIndex(rowIndex);
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

    final int dataRowIndex = _dataGridRows.indexOf(dataGridRow);
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

      final rowIndex = _dataGridRows.indexOf(dataGridRow);
      final rowData = getRowData(rowIndex);

      return _DropdownEditor(
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

/// Searchable dropdown editor for cells with dropdown type
class _DropdownEditor extends StatefulWidget {
  final String currentValue;
  final Future<List<Map<String, String>>> Function(Map<String, dynamic> rowData)
  optionsProvider;
  final Map<String, dynamic> rowData;
  final ColorScheme colorScheme;
  final ValueChanged<String?> onChanged;

  const _DropdownEditor({
    required this.currentValue,
    required this.optionsProvider,
    required this.rowData,
    required this.colorScheme,
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
        // Pre-fill search box with type and value from BOM line
        // For non-ICs (passives), also include package
        final requiredAttrs =
            widget.rowData['required_attributes'] as Map<String, dynamic>?;
        final prefillTerms = <String>[];

        if (requiredAttrs != null) {
          final pkg = requiredAttrs['size']?.toString().trim() ?? '';
          final type = requiredAttrs['part_type']?.toString().trim() ?? '';
          final value = requiredAttrs['value']?.toString().trim() ?? '';

          // Only include package for non-ICs (passives like resistors, capacitors, etc.)
          if (pkg.isNotEmpty && type != 'ic') prefillTerms.add(pkg);
          if (type.isNotEmpty) prefillTerms.add(type);
          if (value.isNotEmpty) prefillTerms.add(value);
        }

        final prefillText = prefillTerms.join(' ');

        setState(() {
          _allOptions = options;
          _filteredOptions = options;
          _loading = false;
          _searchController.text = prefillText;
        });
        // Auto-open dropdown after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusNode.requestFocus();
            // Select all text so user can easily delete it
            _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            );
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

    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOptions = _allOptions!;
      } else {
        // Split query by spaces for AND logic (all terms must match)
        final terms =
            query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

        _filteredOptions =
            _allOptions!.where((option) {
              final id = option['id']?.toLowerCase() ?? '';
              final partNum = option['part_#']?.toLowerCase() ?? '';
              final type = option['type']?.toLowerCase() ?? '';
              final value = option['value']?.toLowerCase() ?? '';
              final pkg = option['package']?.toLowerCase() ?? '';
              final location = option['location']?.toLowerCase() ?? '';
              final description = option['description']?.toLowerCase() ?? '';

              // Combine all searchable fields
              final searchableText =
                  '$id $partNum $type $value $pkg $location $description';

              // ALL terms must be present (AND logic)
              return terms.every((term) => searchableText.contains(term));
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
      builder:
          (context) => Positioned(
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
                    border: Border.all(
                      color: widget.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child:
                      _filteredOptions.isEmpty
                          ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'No matches found',
                              style: TextStyle(
                                color: widget.colorScheme.onSurfaceVariant,
                              ),
                            ),
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
    final description = option['description'] ?? '';

    final isSelected = id == widget.currentValue;

    // Build main display line: Package + Value (most important for passives)
    final mainParts = <String>[];
    if (pkg.isNotEmpty) mainParts.add(pkg);
    if (value.isNotEmpty) mainParts.add(value);
    final mainLine =
        mainParts.isNotEmpty
            ? mainParts.join(' ')
            : (description.isNotEmpty ? description : type);

    return InkWell(
      onTap: () {
        _removeOverlay();
        widget.onChanged(id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? widget.colorScheme.primaryContainer.withValues(alpha: 0.45)
                  : null,
          border: Border(
            bottom: BorderSide(color: widget.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main line: package + value (most important)
            Row(
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: widget.colorScheme.primary,
                    ),
                  ),
                Expanded(
                  child: Text(
                    mainLine,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                // Stock indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
            // Second line: part# (if available) + location
            Row(
              children: [
                if (partNum.isNotEmpty) ...[
                  Icon(
                    Icons.tag,
                    size: 12,
                    color: widget.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      partNum,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(
                  Icons.location_on,
                  size: 12,
                  color: widget.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location.isEmpty ? '(no location)' : location,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
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
    if (qty == 0) return widget.colorScheme.error;
    if (qty < 10) return widget.colorScheme.secondary;
    return widget.colorScheme.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading matches...',
              style: TextStyle(
                fontSize: 12,
                color: widget.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_allOptions == null || _allOptions!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'No inventory matches found',
          style: TextStyle(
            color: widget.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
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
            hintStyle: TextStyle(
              fontSize: 13,
              color: widget.colorScheme.onSurfaceVariant,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 4,
            ),
            border: InputBorder.none,
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => _searchController.clear(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                    : const Icon(Icons.search, size: 16),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
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

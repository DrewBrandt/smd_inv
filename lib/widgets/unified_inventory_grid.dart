// lib/widgets/unified_inventory_grid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../data/firebase_datagrid_source.dart';
import '../data/unified_firestore_streams.dart';
import '../models/columns.dart';
import '../services/datagrid_column_manager.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class UnifiedInventoryGrid extends StatefulWidget {
  final String searchQuery;
  final List<String>? typeFilter;
  final List<String>? packageFilter;
  final List<String>? locationFilter;

  const UnifiedInventoryGrid({
    super.key,
    this.searchQuery = '',
    this.typeFilter,
    this.packageFilter,
    this.locationFilter,
  });

  @override
  State<UnifiedInventoryGrid> createState() => _UnifiedInventoryGridState();
}

class _UnifiedInventoryGridState extends State<UnifiedInventoryGrid>
    with AutomaticKeepAliveClientMixin<UnifiedInventoryGrid> {
  @override
  bool get wantKeepAlive => true;

  DataGridColumnManager? _columnManager;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _initColumnManager();
  }

  Future<void> _initColumnManager() async {
    final columns = UnifiedInventoryColumns.all;
    _columnManager = DataGridColumnManager(
      persistKey: 'inventory_unified',
      columns: columns.map((c) => GridColumnConfig(field: c.field, label: c.label)).toList(),
    );
    await _columnManager!.loadSavedWidths();
    setState(() => _prefsLoaded = true);
  }

  List<Doc> _filterDocs(List<Doc> docs) {
    var filtered = docs;

    // Apply filter chips
    if (widget.typeFilter != null && widget.typeFilter!.isNotEmpty) {
      filtered =
          filtered.where((d) {
            final type = d.data()['type']?.toString() ?? '';
            return widget.typeFilter!.contains(type);
          }).toList();
    }

    if (widget.packageFilter != null && widget.packageFilter!.isNotEmpty) {
      filtered =
          filtered.where((d) {
            final pkg = d.data()['package']?.toString() ?? '';
            return widget.packageFilter!.contains(pkg);
          }).toList();
    }

    if (widget.locationFilter != null && widget.locationFilter!.isNotEmpty) {
      filtered =
          filtered.where((d) {
            final loc = d.data()['location']?.toString() ?? '';
            return widget.locationFilter!.contains(loc);
          }).toList();
    }

    // Apply search query (comma-separated AND logic)
    final query = widget.searchQuery.trim();
    if (query.isEmpty) return filtered;

    final terms = query.split(',').map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return filtered;

    return filtered.where((d) {
      final m = d.data();
      final searchableText = m.values.map((v) => v?.toString().toLowerCase() ?? '').join(' ');

      // ALL terms must be present (AND logic)
      return terms.every((term) => searchableText.contains(term));
    }).toList();
  }

  bool _onColumnResizeStart(ColumnResizeStartDetails d) {
    _columnManager?.onColumnResizeStart();
    return true;
  }

  bool _onColumnResizeUpdate(ColumnResizeUpdateDetails d) {
    final min = _columnManager?.getMinWidth(d.column.columnName) ?? 140;
    final clamped = d.width < min ? min : d.width;
    _columnManager?.onColumnResizeUpdate(d.column.columnName, clamped);
    setState(() {});
    return true;
  }

  void _onColumnResizeEnd(ColumnResizeEndDetails d) {
    _columnManager?.onColumnResizeEnd();
  }

  Future<void> _showRowMenu({
    required Offset globalPosition,
    required int gridRowIndex,
    required FirestoreDataSource source,
  }) async {
    // header is row 0
    if (gridRowIndex <= 0) return;
    final docIndex = gridRowIndex - 1;
    if (docIndex < 0 || docIndex >= source.rowCount) return;

    final doc = source.docAt(docIndex);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx, globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'copy-id', child: Text('Copy Reference')),
        PopupMenuItem(value: 'delete', child: Text('Delete Row')),
      ],
    );

    if (selected == null) return;

    switch (selected) {
      case 'copy-id':
        await Clipboard.setData(ClipboardData(text: doc.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document ID copied')));
        }
        break;
      case 'delete':
        await source.deleteAt(docIndex);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document deleted')));
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final headerBg = Theme.of(context).colorScheme.primaryContainer;
    final headerFg = Theme.of(context).colorScheme.onPrimaryContainer;
    final columns = UnifiedInventoryColumns.all; // Always show all columns now

    return StreamBuilder<List<Doc>>(
      stream: inventoryStream(typeFilter: null), // Get all data, filter in _filterDocs
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = _filterDocs(snap.data!);
        final source = FirestoreDataSource(docs: docs, columns: columns, colorScheme: Theme.of(context).colorScheme);

        return LayoutBuilder(
          builder: (context, constraints) {
            // Use the column manager to calculate widths
            final widths = _columnManager?.calculateWidths(constraints) ?? {};

            final gridColumns =
                columns
                    .map(
                      (col) => GridColumn(
                        columnName: col.field,
                        width: widths[col.field]!,
                        label: Container(
                          color: headerBg,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            col.label,
                            style: TextStyle(color: headerFg, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList();

            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SfDataGridTheme(
                    data: SfDataGridThemeData(
                      headerColor: headerBg,
                      columnResizeIndicatorColor: Theme.of(context).colorScheme.primary,
                      columnResizeIndicatorStrokeWidth: 3.0,
                      columnDragIndicatorColor: Theme.of(context).colorScheme.secondary,
                      columnDragIndicatorStrokeWidth: 3.0,
                    ),
                    child: SfDataGrid(
                      shrinkWrapRows: true,
                      source: source,
                      columns: gridColumns,
                      columnWidthMode: ColumnWidthMode.none,
                      columnResizeMode: ColumnResizeMode.onResizeEnd,
                      allowSorting: true,
                      allowMultiColumnSorting: true,
                      rowHeight: 36,
                      headerRowHeight: 40,
                      frozenColumnsCount: 1,
                      gridLinesVisibility: GridLinesVisibility.horizontal,
                      headerGridLinesVisibility: GridLinesVisibility.horizontal,
                      allowEditing: true,
                      selectionMode: SelectionMode.single,
                      navigationMode: GridNavigationMode.cell,
                      editingGestureType: EditingGestureType.doubleTap,
                      allowColumnsDragging: true,
                      allowColumnsResizing: true,
                      onColumnResizeStart: _onColumnResizeStart,
                      onColumnResizeUpdate: _onColumnResizeUpdate,
                      onColumnResizeEnd: _onColumnResizeEnd,
                      onCellSecondaryTap:
                          (details) => _showRowMenu(
                            globalPosition: details.globalPosition,
                            gridRowIndex: details.rowColumnIndex.rowIndex,
                            source: source,
                          ),
                      onCellLongPress:
                          (details) => _showRowMenu(
                            globalPosition: details.globalPosition,
                            gridRowIndex: details.rowColumnIndex.rowIndex,
                            source: source,
                          ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

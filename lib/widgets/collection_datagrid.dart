// lib/widgets/collection_datagrid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/data/list_map_source.dart';
import 'package:smd_inv/data/unified_firestore_streams.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../data/firebase_datagrid_source.dart'; // keeps your FirestoreDataSource
import '../models/columns.dart';
import '../services/datagrid_column_manager.dart';


/// LEGACY: This widget is for non-inventory collections.
/// For inventory, use UnifiedInventoryGrid instead.
/// 
typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class CollectionDataGrid extends StatefulWidget {
  /// Firestore mode (original behavior)
  final String? collection;

  /// Local list mode (new)
  final List<Map<String, dynamic>>? rows;
  final ValueChanged<List<Map<String, dynamic>>>? onRowsChanged;

  final List<ColumnSpec> columns;
  final String searchQuery;

  /// Optional key for persisting widths; if null we’ll use collection name or “local”.
  final String? persistKey;

  const CollectionDataGrid({
    super.key,
    required this.columns,
    this.collection, // stream mode if provided
    this.rows, // list mode if provided
    this.onRowsChanged,
    this.searchQuery = '',
    this.persistKey,
  }) : assert((collection != null) ^ (rows != null), 'Provide either `collection` OR `rows` (but not both)');

  @override
  State<CollectionDataGrid> createState() => _CollectionDataGridState();
}

class _CollectionDataGridState extends State<CollectionDataGrid>
    with AutomaticKeepAliveClientMixin<CollectionDataGrid> {
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
    _columnManager = DataGridColumnManager(
      persistKey: widget.persistKey ?? widget.collection ?? 'local',
      columns: widget.columns.map((c) => GridColumnConfig(field: c.field, label: c.label)).toList(),
    );
    await _columnManager!.loadSavedWidths();
    setState(() => _prefsLoaded = true);
  }

  // --- filtering (only used in Firestore mode because list mode is your state)
  List<Doc> _filterDocs(List<Doc> docs, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return docs;
    return docs.where((d) {
      final m = d.data();
      return m.values.any((v) => v.toString().toLowerCase().contains(s));
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final headerBg = Theme.of(context).colorScheme.primaryContainer;
    final headerFg = Theme.of(context).colorScheme.onPrimaryContainer;

    Widget buildGrid(DataGridSource source) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Use the column manager to calculate widths
          final widths = _columnManager?.calculateWidths(constraints) ?? {};

          final gridColumns =
              widget.columns
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
              padding: const EdgeInsets.only(bottom:1),
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
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // ── Mode A: Local list (no Firestore stream)
    if (widget.rows != null) {
      if (!_prefsLoaded) return const Center(child: CircularProgressIndicator());
      final source = ListMapDataSource(
        rows: widget.rows!,
        columns: widget.columns,
        colorScheme: Theme.of(context).colorScheme,
        onCommit: (rowIndex, field, parsedValue) {
          // Update the local list in-place
          widget.rows![rowIndex][field] = parsedValue;
          widget.onRowsChanged?.call(widget.rows!);
        },
      );
      return buildGrid(source);
    }

    // ── Mode B: Firestore (original)
    return StreamBuilder<List<Doc>>(
      stream: collectionStream(widget.collection!), // non-null here by assert
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = _filterDocs(snap.data!, widget.searchQuery);
        final source = FirestoreDataSource(
          docs: docs,
          columns: widget.columns,
          colorScheme: Theme.of(context).colorScheme,
        );
        return buildGrid(source);
      },
    );
  }
}

// lib/widgets/unified_data_grid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../data/firebase_datagrid_source.dart';
import '../data/list_map_source.dart';
import '../data/unified_firestore_streams.dart';
import '../models/columns.dart';
import '../services/datagrid_column_manager.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// A unified data grid widget that can display data from multiple sources:
/// - Firestore collections with real-time streaming
/// - Firestore inventory with advanced filtering
/// - Local list data
///
/// Features:
/// - Column resizing and reordering
/// - Inline editing
/// - Search and filtering
/// - Row context menu (copy ID, delete)
/// - Persistent column widths
class UnifiedDataGrid extends StatefulWidget {
  // ── Data Source Options (provide exactly ONE) ──

  /// Option 1: Generic Firestore collection (streamed)
  final String? collection;

  /// Option 2: Inventory mode - uses inventoryStream with advanced filtering
  final bool useInventoryStream;

  /// Option 3: Local list mode (no Firestore)
  final List<Map<String, dynamic>>? rows;
  final ValueChanged<List<Map<String, dynamic>>>? onRowsChanged;

  // ── Display Configuration ──

  /// The columns to display
  final List<ColumnSpec> columns;

  /// Search query for filtering (applies to all modes)
  final String searchQuery;

  /// Inventory-specific filters (only used when useInventoryStream=true)
  final List<String>? typeFilter;
  final List<String>? packageFilter;
  final List<String>? locationFilter;

  // ── UI Options ──

  /// Key for persisting column widths (defaults to collection name or 'local')
  final String? persistKey;

  /// Whether to enable row context menu (copy ID, delete)
  final bool enableRowMenu;

  /// Number of frozen columns (defaults to 1)
  final int frozenColumnsCount;

  const UnifiedDataGrid({
    super.key,
    required this.columns,
    this.collection,
    this.useInventoryStream = false,
    this.rows,
    this.onRowsChanged,
    this.searchQuery = '',
    this.typeFilter,
    this.packageFilter,
    this.locationFilter,
    this.persistKey,
    this.enableRowMenu = true,
    this.frozenColumnsCount = 1,
  }) : assert(
          (collection != null && !useInventoryStream && rows == null) ||
          (collection == null && useInventoryStream && rows == null) ||
          (collection == null && !useInventoryStream && rows != null),
          'Provide exactly ONE data source: collection, useInventoryStream=true, or rows',
        );

  /// Factory constructor for Firestore collections
  factory UnifiedDataGrid.collection({
    Key? key,
    required String collection,
    required List<ColumnSpec> columns,
    String searchQuery = '',
    String? persistKey,
    bool enableRowMenu = true,
    int frozenColumnsCount = 1,
  }) {
    return UnifiedDataGrid(
      key: key,
      collection: collection,
      columns: columns,
      searchQuery: searchQuery,
      persistKey: persistKey,
      enableRowMenu: enableRowMenu,
      frozenColumnsCount: frozenColumnsCount,
    );
  }

  /// Factory constructor for inventory stream with filters
  factory UnifiedDataGrid.inventory({
    Key? key,
    required List<ColumnSpec> columns,
    String searchQuery = '',
    List<String>? typeFilter,
    List<String>? packageFilter,
    List<String>? locationFilter,
    String? persistKey,
    bool enableRowMenu = true,
    int frozenColumnsCount = 1,
  }) {
    return UnifiedDataGrid(
      key: key,
      useInventoryStream: true,
      columns: columns,
      searchQuery: searchQuery,
      typeFilter: typeFilter,
      packageFilter: packageFilter,
      locationFilter: locationFilter,
      persistKey: persistKey ?? 'inventory_unified',
      enableRowMenu: enableRowMenu,
      frozenColumnsCount: frozenColumnsCount,
    );
  }

  /// Factory constructor for local list data
  factory UnifiedDataGrid.local({
    Key? key,
    required List<Map<String, dynamic>> rows,
    required List<ColumnSpec> columns,
    ValueChanged<List<Map<String, dynamic>>>? onRowsChanged,
    String searchQuery = '',
    String? persistKey,
    bool enableRowMenu = false,
    int frozenColumnsCount = 1,
  }) {
    return UnifiedDataGrid(
      key: key,
      rows: rows,
      onRowsChanged: onRowsChanged,
      columns: columns,
      searchQuery: searchQuery,
      persistKey: persistKey ?? 'local',
      enableRowMenu: enableRowMenu,
      frozenColumnsCount: frozenColumnsCount,
    );
  }

  @override
  State<UnifiedDataGrid> createState() => _UnifiedDataGridState();
}

class _UnifiedDataGridState extends State<UnifiedDataGrid>
    with AutomaticKeepAliveClientMixin<UnifiedDataGrid> {
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
    final key = widget.persistKey ??
                widget.collection ??
                (widget.useInventoryStream ? 'inventory_unified' : 'local');

    _columnManager = DataGridColumnManager(
      persistKey: key,
      columns: widget.columns.map((c) => GridColumnConfig(field: c.field, label: c.label)).toList(),
    );
    await _columnManager!.loadSavedWidths();
    setState(() => _prefsLoaded = true);
  }

  // ── Filtering Logic ──

  /// Filters documents for inventory stream mode
  List<Doc> _filterInventoryDocs(List<Doc> docs) {
    var filtered = docs;

    // Apply filter chips
    if (widget.typeFilter != null && widget.typeFilter!.isNotEmpty) {
      filtered = filtered.where((d) {
        final type = d.data()['type']?.toString() ?? '';
        return widget.typeFilter!.contains(type);
      }).toList();
    }

    if (widget.packageFilter != null && widget.packageFilter!.isNotEmpty) {
      filtered = filtered.where((d) {
        final pkg = d.data()['package']?.toString() ?? '';
        return widget.packageFilter!.contains(pkg);
      }).toList();
    }

    if (widget.locationFilter != null && widget.locationFilter!.isNotEmpty) {
      filtered = filtered.where((d) {
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

  /// Filters documents for simple collection stream mode
  List<Doc> _filterSimpleDocs(List<Doc> docs) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return docs;

    return docs.where((d) {
      final m = d.data();
      return m.values.any((v) => v.toString().toLowerCase().contains(query));
    }).toList();
  }

  // ── Column Resize Handlers ──

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

  // ── Row Context Menu ──

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

  // ── Grid Builder ──

  Widget _buildGrid(DataGridSource source, {FirestoreDataSource? firestoreSource}) {
    final headerBg = Theme.of(context).colorScheme.primaryContainer;
    final headerFg = Theme.of(context).colorScheme.onPrimaryContainer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _columnManager?.calculateWidths(constraints) ?? {};

        final gridColumns = widget.columns
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
                  frozenColumnsCount: widget.frozenColumnsCount,
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
                  onCellSecondaryTap: widget.enableRowMenu && firestoreSource != null
                      ? (details) => _showRowMenu(
                            globalPosition: details.globalPosition,
                            gridRowIndex: details.rowColumnIndex.rowIndex,
                            source: firestoreSource,
                          )
                      : null,
                  onCellLongPress: widget.enableRowMenu && firestoreSource != null
                      ? (details) => _showRowMenu(
                            globalPosition: details.globalPosition,
                            gridRowIndex: details.rowColumnIndex.rowIndex,
                            source: firestoreSource,
                          )
                      : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // ── Mode 1: Local list (no Firestore) ──
    if (widget.rows != null) {
      if (!_prefsLoaded) return const Center(child: CircularProgressIndicator());

      final source = ListMapDataSource(
        rows: widget.rows!,
        columns: widget.columns,
        colorScheme: Theme.of(context).colorScheme,
        onCommit: (rowIndex, field, parsedValue) {
          widget.rows![rowIndex][field] = parsedValue;
          widget.onRowsChanged?.call(widget.rows!);
        },
      );
      return _buildGrid(source);
    }

    // ── Mode 2: Inventory stream with advanced filtering ──
    if (widget.useInventoryStream) {
      return StreamBuilder<List<Doc>>(
        stream: inventoryStream(typeFilter: null), // Get all, filter locally
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !_prefsLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = _filterInventoryDocs(snap.data!);
          final source = FirestoreDataSource(
            docs: docs,
            columns: widget.columns,
            colorScheme: Theme.of(context).colorScheme,
          );

          return _buildGrid(source, firestoreSource: source);
        },
      );
    }

    // ── Mode 3: Generic Firestore collection ──
    return StreamBuilder<List<Doc>>(
      stream: collectionStream(widget.collection!),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = _filterSimpleDocs(snap.data!);
        final source = FirestoreDataSource(
          docs: docs,
          columns: widget.columns,
          colorScheme: Theme.of(context).colorScheme,
        );

        return _buildGrid(source, firestoreSource: source);
      },
    );
  }
}

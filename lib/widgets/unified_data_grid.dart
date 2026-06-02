// lib/widgets/unified_data_grid.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../data/firebase_datagrid_source.dart';
import '../data/list_map_source.dart';
import '../data/inventory_repo.dart';
import '../models/columns.dart';
import '../services/datagrid_column_manager.dart';
import '../services/inventory_history_service.dart';
import '../utils/browser_context_menu_suppressor.dart';

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
  final InventoryRepo? inventoryRepo;

  // ── Display Configuration ──

  /// The columns to display
  final List<ColumnSpec> columns;

  /// Search query for filtering (applies to all modes)
  final String searchQuery;

  /// Inventory-specific filters (only used when useInventoryStream=true)
  final List<String>? typeFilter;
  final List<String>? packageFilter;
  final List<String>? locationFilter;

  /// Optional history service for recording edits and deletes (inventory mode only)
  final InventoryHistoryService? historyService;

  // ── UI Options ──

  /// Key for persisting column widths (defaults to collection name or 'local')
  final String? persistKey;

  /// Whether to enable row context menu (copy ID, delete)
  final bool enableRowMenu;

  /// Whether cell editing is enabled.
  final bool allowEditing;

  /// Number of frozen columns (defaults to 1)
  final int frozenColumnsCount;

  const UnifiedDataGrid({
    super.key,
    required this.columns,
    this.collection,
    this.useInventoryStream = false,
    this.rows,
    this.onRowsChanged,
    this.inventoryRepo,
    this.searchQuery = '',
    this.typeFilter,
    this.packageFilter,
    this.locationFilter,
    this.historyService,
    this.persistKey,
    this.enableRowMenu = true,
    this.allowEditing = true,
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
    bool allowEditing = true,
    int frozenColumnsCount = 1,
  }) {
    return UnifiedDataGrid(
      key: key,
      collection: collection,
      columns: columns,
      searchQuery: searchQuery,
      persistKey: persistKey,
      enableRowMenu: enableRowMenu,
      allowEditing: allowEditing,
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
    InventoryHistoryService? historyService,
    String? persistKey,
    bool enableRowMenu = true,
    bool allowEditing = true,
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
      historyService: historyService,
      persistKey: persistKey ?? 'inventory_unified',
      enableRowMenu: enableRowMenu,
      allowEditing: allowEditing,
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
    bool allowEditing = true,
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
      allowEditing: allowEditing,
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
  InventoryRepo? _inventoryRepo;
  final _gridBoundsKey = GlobalKey();
  final _browserContextMenuSuppressor = BrowserContextMenuSuppressor();

  // ── Firestore-backed state (inventory & collection modes) ──
  // The stream is subscribed once and only re-subscribed when the *server-side*
  // filters change — never on a search keystroke. The data source is reused
  // across rebuilds instead of being recreated each time.
  StreamSubscription<List<Doc>>? _docsSub;
  List<Doc> _allDocs = const [];
  FirestoreDataSource? _firestoreSource;
  Object? _streamError;
  bool _firstSnapshotReceived = false;

  /// Cache of the lowercased searchable text per document id, so that typing
  /// in the search box doesn't re-stringify every document on every keystroke.
  /// Cleared whenever a fresh snapshot arrives.
  final Map<String, String> _searchTextCache = {};

  bool get _isFirestoreMode => widget.rows == null;

  @override
  void initState() {
    super.initState();
    if (_isFirestoreMode) {
      _inventoryRepo = widget.inventoryRepo ?? InventoryRepo();
      _subscribeDocs();
    }
    _initColumnManager();
  }

  @override
  void didUpdateWidget(covariant UnifiedDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isFirestoreMode) return;

    // Re-subscribe only when something that affects the *query* changes.
    final modeOrFiltersChanged =
        oldWidget.useInventoryStream != widget.useInventoryStream ||
        oldWidget.collection != widget.collection ||
        !listEquals(oldWidget.typeFilter, widget.typeFilter) ||
        !listEquals(oldWidget.packageFilter, widget.packageFilter) ||
        !listEquals(oldWidget.locationFilter, widget.locationFilter);

    if (modeOrFiltersChanged) {
      _subscribeDocs();
    } else if (oldWidget.searchQuery != widget.searchQuery) {
      // Search is client-side only: re-filter the cached docs after this
      // build completes (so we don't call notifyListeners during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFilter();
      });
    }
  }

  @override
  void dispose() {
    _browserContextMenuSuppressor.dispose();
    _docsSub?.cancel();
    super.dispose();
  }

  void _updateBrowserContextMenuBounds(bool enabled) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!enabled) {
        _browserContextMenuSuppressor.updateBounds(null);
        return;
      }

      final renderObject = _gridBoundsKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) return;
      final topLeft = renderObject.localToGlobal(Offset.zero);
      _browserContextMenuSuppressor.updateBounds(topLeft & renderObject.size);
    });
  }

  /// (Re)subscribes to the appropriate Firestore stream. Called once on init
  /// and again only when the mode or a server-side filter changes.
  void _subscribeDocs() {
    _docsSub?.cancel();
    _firstSnapshotReceived = false;
    _streamError = null;

    final Stream<List<Doc>> stream =
        widget.useInventoryStream
            ? _inventoryRepo!.streamFiltered(
              typeFilter: widget.typeFilter,
              packageFilter: widget.packageFilter,
              locationFilter: widget.locationFilter,
            )
            : _inventoryRepo!.streamCollection(widget.collection!);

    _docsSub = stream.listen(
      (docs) {
        _allDocs = docs;
        _searchTextCache.clear();
        _applyFilter();
        if (mounted) setState(() => _firstSnapshotReceived = true);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _streamError = e;
            _firstSnapshotReceived = true;
          });
        }
      },
    );
  }

  /// Applies the client-side search filter to the cached docs and updates the
  /// existing data source in place (creating it on first use).
  void _applyFilter() {
    final docs =
        widget.useInventoryStream
            ? _filterInventoryDocs(_allDocs)
            : _filterSimpleDocs(_allDocs);

    final source = _firestoreSource;
    if (source == null) {
      _firestoreSource = FirestoreDataSource(
        docs: docs,
        columns: widget.columns,
        colorScheme: Theme.of(context).colorScheme,
        historyService:
            widget.useInventoryStream ? widget.historyService : null,
      );
    } else {
      source.updateDocs(docs);
    }
  }

  Future<void> _initColumnManager() async {
    final key =
        widget.persistKey ??
        widget.collection ??
        (widget.useInventoryStream ? 'inventory_unified' : 'local');

    _columnManager = DataGridColumnManager(
      persistKey: key,
      columns:
          widget.columns
              .map((c) => GridColumnConfig(field: c.field, label: c.label))
              .toList(),
    );
    await _columnManager!.loadSavedWidths();
    setState(() => _prefsLoaded = true);
  }

  // ── Filtering Logic ──

  /// Filters documents for inventory stream mode
  List<Doc> _filterInventoryDocs(List<Doc> docs) {
    // Apply search query (comma-separated AND logic)
    final query = widget.searchQuery.trim();
    if (query.isEmpty) return docs;

    final terms =
        query
            .split(',')
            .map((t) => t.trim().toLowerCase())
            .where((t) => t.isNotEmpty)
            .toList();
    if (terms.isEmpty) return docs;

    return docs.where((d) {
      final searchableText = _searchableTextFor(d);
      // ALL terms must be present (AND logic)
      return terms.every((term) => searchableText.contains(term));
    }).toList();
  }

  /// Filters documents for simple collection stream mode
  List<Doc> _filterSimpleDocs(List<Doc> docs) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return docs;

    return docs.where((d) => _searchableTextFor(d).contains(query)).toList();
  }

  /// Lowercased, space-joined string of all field values for a document,
  /// memoized per document id (cache is cleared on each new snapshot).
  String _searchableTextFor(Doc d) {
    return _searchTextCache.putIfAbsent(
      d.id,
      () => d
          .data()
          .values
          .map((v) => v?.toString().toLowerCase() ?? '')
          .join(' '),
    );
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
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Document ID copied')));
        }
        break;
      case 'delete':
        await source.deleteAt(docIndex);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Document deleted')));
        }
        break;
    }
  }

  // ── Grid Builder ──

  Widget _buildGrid(
    DataGridSource source, {
    FirestoreDataSource? firestoreSource,
  }) {
    final headerBg = Theme.of(context).colorScheme.primaryContainer;
    final headerFg = Theme.of(context).colorScheme.onPrimaryContainer;
    final rowMenuEnabled =
        widget.enableRowMenu && widget.allowEditing && firestoreSource != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        _updateBrowserContextMenuBounds(rowMenuEnabled);
        final widths = _columnManager?.calculateWidths(constraints) ?? {};

        final gridColumns =
            widget.columns
                .map(
                  (col) => GridColumn(
                    columnName: col.field,
                    width:
                        widths[col.field] ??
                        (_columnManager?.getMinWidth(col.field) ?? 140),
                    allowEditing: col.editable,
                    label: Container(
                      color: headerBg,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        col.label,
                        style: TextStyle(
                          color: headerFg,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                )
                .toList();

        return DecoratedBox(
          key: _gridBoundsKey,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SfDataGridTheme(
                data: SfDataGridThemeData(
                  headerColor: headerBg,
                  columnResizeIndicatorColor:
                      Theme.of(context).colorScheme.primary,
                  columnResizeIndicatorStrokeWidth: 3.0,
                  columnDragIndicatorColor:
                      Theme.of(context).colorScheme.secondary,
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
                  allowEditing: widget.allowEditing,
                  selectionMode: SelectionMode.single,
                  navigationMode: GridNavigationMode.cell,
                  editingGestureType:
                      widget.allowEditing
                          ? EditingGestureType.doubleTap
                          : EditingGestureType.tap,
                  allowColumnsDragging: true,
                  allowColumnsResizing: true,
                  onColumnResizeStart: _onColumnResizeStart,
                  onColumnResizeUpdate: _onColumnResizeUpdate,
                  onColumnResizeEnd: _onColumnResizeEnd,
                  onCellSecondaryTap:
                      rowMenuEnabled
                          ? (details) => _showRowMenu(
                            globalPosition: details.globalPosition,
                            gridRowIndex: details.rowColumnIndex.rowIndex,
                            source: firestoreSource,
                          )
                          : null,
                  onCellLongPress:
                      rowMenuEnabled
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
      if (!_prefsLoaded) {
        return const Center(child: CircularProgressIndicator());
      }

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

    // ── Modes 2 & 3: Firestore-backed (inventory stream or generic collection) ──
    // Data is streamed via a manually-managed subscription (see _subscribeDocs)
    // and rendered from a single reused FirestoreDataSource.
    if (_streamError != null) {
      return Center(child: Text('Error: $_streamError'));
    }
    if (!_prefsLoaded || !_firstSnapshotReceived || _firestoreSource == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildGrid(_firestoreSource!, firestoreSource: _firestoreSource!);
  }
}

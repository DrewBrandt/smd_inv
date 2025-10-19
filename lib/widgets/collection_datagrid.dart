// lib/widgets/collection_datagrid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smd_inv/data/list_map_source.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../data/firebase_datagrid_source.dart'; // keeps your FirestoreDataSource
import '../data/firestore_streams.dart';
import '../models/columns.dart';

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

  final Map<String, double> _userWidths = {};
  bool _prefsLoaded = false;
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
    _loadSavedWidths();
  }

  Future<void> _loadSavedWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'dg_widths:${widget.persistKey ?? widget.collection ?? "local"}';
    final saved = prefs.getStringList(key) ?? const [];
    for (final entry in saved) {
      final eq = entry.indexOf('=');
      if (eq > 0) {
        final f = entry.substring(0, eq);
        final w = double.tryParse(entry.substring(eq + 1));
        if (w != null && w > 0) _userWidths[f] = w;
      }
    }
    setState(() => _prefsLoaded = true);
  }

  Future<void> _saveWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'dg_widths:${widget.persistKey ?? widget.collection ?? "local"}';
    final list = _userWidths.entries.map((e) => '${e.key}=${e.value}').toList();
    await prefs.setStringList(key, list);
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

  // --- minimum widths
  double _minWidthFor(String field) {
    final f = field.toLowerCase();
    if (f == 'qty' || f == 'quantity' || f == 'count') return 84;
    if (f == 'notes' || f == 'description' || f == 'desc') return 320;
    if (f == 'datasheet' || f == 'url' || f == 'link') return 220;
    if (f == 'id' || f.endsWith('_id')) return 140;
    if (f == 'size' || f == 'value') return 120;
    if (f == 'location') return 160;
    if (f == 'parttype' || f == 'part_type' || f == 'type' || f == 'category') return 160;
    return 140;
  }

  // --- weights for extra space (0.0 means do not grow beyond min)
  double _weightFor(ColumnSpec col) {
    if (col.kind == CellKind.integer || col.kind == CellKind.decimal) return 0.0;
    final f = col.field.toLowerCase();
    if (f == 'notes' || f == 'description' || f == 'desc') return 4.0;
    if (f == 'datasheet' || f == 'url' || f == 'link') return 2.0;
    if (f == 'parttype' || f == 'part_type' || f == 'type' || f == 'category') return 1.5;
    if (f == 'location') return 1.5;
    if (f == 'size' || f == 'qty' || f == 'quantity' || f == 'count' || f == 'value') return 0.0;
    return 1.0;
  }

  bool _onColumnResizeStart(ColumnResizeStartDetails d) {
    _isResizing = true;
    return true;
  }

  bool _onColumnResizeUpdate(ColumnResizeUpdateDetails d) {
    final min = _minWidthFor(d.column.columnName);
    final clamped = d.width < min ? min : d.width;
    _userWidths[d.column.columnName] = clamped;
    setState(() {}); // reflect immediately
    return true;
  }

  void _onColumnResizeEnd(ColumnResizeEndDetails d) {
    _isResizing = false;
    _saveWidths();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final headerBg = Theme.of(context).colorScheme.primaryContainer;
    final headerFg = Theme.of(context).colorScheme.onPrimaryContainer;

    Widget buildGrid(DataGridSource source) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final mins = <String, double>{for (final c in widget.columns) c.field: _minWidthFor(c.field)};
          final weights = <String, double>{for (final c in widget.columns) c.field: _weightFor(c)};
          final widths = <String, double>{for (final c in widget.columns) c.field: mins[c.field]!};

          for (final e in _userWidths.entries) {
            if (widths.containsKey(e.key)) {
              widths[e.key] = e.value < mins[e.key]! ? mins[e.key]! : e.value;
            }
          }

          if (constraints.maxWidth.isFinite && !_isResizing) {
            final maxW = constraints.maxWidth;
            final sumNow = widths.values.fold<double>(0, (a, b) => a + b);
            final extra = maxW - sumNow;
            if (extra > 0) {
              final growable =
                  widget.columns
                      .where((c) => !_userWidths.containsKey(c.field) && (weights[c.field] ?? 0) > 0)
                      .toList();
              final totalWeight = growable.fold<double>(0.0, (a, c) => a + (weights[c.field] ?? 0));
              if (totalWeight > 0) {
                for (final c in growable) {
                  widths[c.field] = widths[c.field]! + extra * ((weights[c.field] ?? 0) / totalWeight);
                }
              } else {
                widths[widget.columns.last.field] = widths[widget.columns.last.field]! + extra;
              }
            }
          }

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

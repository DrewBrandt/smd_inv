// lib/widgets/collection_datagrid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../data/firebase_datagrid_source.dart';
import '../data/firestore_streams.dart';
import '../models/columns.dart';
import 'package:syncfusion_flutter_core/theme.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class CollectionDataGrid extends StatefulWidget {
  final String collection;
  final List<ColumnSpec> columns;
  final String searchQuery;

  const CollectionDataGrid({super.key, required this.collection, required this.columns, this.searchQuery = ''});

  @override
  State<CollectionDataGrid> createState() => _CollectionDataGridState();
}

class _CollectionDataGridState extends State<CollectionDataGrid>
    with AutomaticKeepAliveClientMixin<CollectionDataGrid> {
  @override
  bool get wantKeepAlive => true;

  // Persistent per-collection widths keyed by field name
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
    // Namespaced key per collection so different tables don’t clash
    final key = 'dg_widths:${widget.collection}';
    final saved = prefs.getStringList(key) ?? const [];
    // Format: "field=width"
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
    final key = 'dg_widths:${widget.collection}';
    final list = _userWidths.entries.map((e) => '${e.key}=${e.value}').toList();
    await prefs.setStringList(key, list);
  }

  // --- filtering
  List<Doc> _filter(List<Doc> docs, String q) {
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
    if (col.kind == CellKind.integer || col.kind == CellKind.decimal) return 0.0; // your request
    final f = col.field.toLowerCase();
    if (f == 'notes' || f == 'description' || f == 'desc') return 4.0; // longest
    if (f == 'datasheet' || f == 'url' || f == 'link') return 2.0; // next
    if (f == 'parttype' || f == 'part_type' || f == 'type' || f == 'category') return 1.5;
    if (f == 'location') return 1.5;
    if (f == 'size' || f == 'qty' || f == 'quantity' || f == 'count' || f == 'value') return 0.0;
    return 1.0;
  }

  bool _onColumnResizeStart(ColumnResizeStartDetails d) {
    _isResizing = true;
    return true; // allow the resize per docs
  }

  bool _onColumnResizeUpdate(ColumnResizeUpdateDetails d) {
    final min = _minWidthFor(d.column.columnName);
    final clamped = d.width < min ? min : d.width;

    // Update the app-level column width collection (doc pattern)
    _userWidths[d.column.columnName] = clamped;

    // Rebuild so GridColumns pick up the new width from the collection
    setState(() {});
    return true; // tell the grid to accept this width
  }

  void _onColumnResizeEnd(ColumnResizeEndDetails d) {
    _isResizing = false;
    _saveWidths(); // your existing SharedPreferences persistence
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final headerBg = Theme.of(context).colorScheme.primaryContainer;
    final headerFg = Theme.of(context).colorScheme.onPrimaryContainer;

    return StreamBuilder<List<Doc>>(
      stream: collectionStream(widget.collection),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data ?? [];
        final filteredDocs = _filter(docs, widget.searchQuery);
        final dataSource = FirestoreDataSource(docs: filteredDocs, columns: widget.columns, colorScheme: Theme.of(context).colorScheme);

        return LayoutBuilder(
          builder: (context, constraints) {
            final mins = <String, double>{for (final c in widget.columns) c.field: _minWidthFor(c.field)};
            final weights = <String, double>{for (final c in widget.columns) c.field: _weightFor(c)};

            // Start with mins
            final widths = <String, double>{for (final c in widget.columns) c.field: mins[c.field]!};

            // Apply any user-set widths (doc pattern)
            for (final e in _userWidths.entries) {
              if (widths.containsKey(e.key)) {
                widths[e.key] = e.value < mins[e.key]! ? mins[e.key]! : e.value;
              }
            }

            // Only if not resizing and we know viewport width, distribute extra by weight
            if (constraints.maxWidth.isFinite && !_isResizing) {
              final maxW = constraints.maxWidth;
              final sumNow = widths.values.fold<double>(0, (a, b) => a + b);
              final extra = (maxW - sumNow);
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
                  // No growables—give leftover to last column
                  widths[widget.columns.last.field] = widths[widget.columns.last.field]! + extra;
                }
              }
            }

            final gridColumns =
                widget.columns.map((col) {
                  return GridColumn(
                    columnName: col.field,
                    width: widths[col.field]!, // explicit final width
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
                  );
                }).toList();

            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SfDataGridTheme(
                  data: SfDataGridThemeData(
                    headerColor: headerBg,
                    columnResizeIndicatorColor: Theme.of(context).colorScheme.primary,
                    columnResizeIndicatorStrokeWidth: 3.0,
                    columnDragIndicatorColor: Theme.of(context).colorScheme.secondary,
                    columnDragIndicatorStrokeWidth: 3.0,
                  ),
                  child: SfDataGrid(
                    source: dataSource,
                    columns: gridColumns,
                  
                    // We control exact widths; the grid respects them.
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
                  
                    // Persist widths on drag
                    onColumnResizeStart: _onColumnResizeStart,
                    onColumnResizeUpdate: _onColumnResizeUpdate,
                    onColumnResizeEnd: _onColumnResizeEnd,
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

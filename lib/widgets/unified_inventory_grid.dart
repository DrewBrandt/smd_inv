// lib/widgets/unified_inventory_grid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../data/firebase_datagrid_source.dart';
import '../data/unified_firestore_streams.dart';
import '../models/columns.dart';
import '../models/unified_columns.dart';

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
    final key = 'dg_widths:inventory_unified';
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
    final key = 'dg_widths:inventory_unified';
    final list = _userWidths.entries.map((e) => '${e.key}=${e.value}').toList();
    await prefs.setStringList(key, list);
  }

  List<Doc> _filterDocs(List<Doc> docs) {
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

  double _minWidthFor(String field) {
    final f = field.toLowerCase();
    if (f == 'qty' || f == 'quantity' || f == 'count') return 84;
    if (f == 'notes' || f == 'description' || f == 'desc') return 320;
    if (f == 'datasheet' || f == 'url' || f == 'link' || f == 'vendor_link') return 220;
    if (f == 'part_#' || f.endsWith('_id')) return 180;
    if (f == 'size' || f == 'value' || f == 'package') return 120;
    if (f == 'location') return 160;
    if (f == 'type' || f == 'category') return 120;
    return 140;
  }

  double _weightFor(ColumnSpec col) {
    if (col.kind == CellKind.integer || col.kind == CellKind.decimal) return 0.0;
    final f = col.field.toLowerCase();
    if (f == 'notes' || f == 'description' || f == 'desc') return 4.0;
    if (f == 'datasheet' || f == 'url' || f == 'link' || f == 'vendor_link') return 2.0;
    if (f == 'type' || f == 'category') return 1.0;
    if (f == 'location') return 1.5;
    if (f == 'size' || f == 'qty' || f == 'quantity' || f == 'count' || f == 'value' || f == 'package') return 0.0;
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
    setState(() {});
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
    final columns = UnifiedInventoryColumns.all; // Always show all columns now

    return StreamBuilder<List<Doc>>(
      stream: inventoryStream(typeFilter: null), // Get all data, filter in _filterDocs
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = _filterDocs(snap.data!);
        final source = FirestoreDataSource(
          docs: docs,
          columns: columns,
          colorScheme: Theme.of(context).colorScheme,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final mins = <String, double>{for (final c in columns) c.field: _minWidthFor(c.field)};
            final weights = <String, double>{for (final c in columns) c.field: _weightFor(c)};
            final widths = <String, double>{for (final c in columns) c.field: mins[c.field]!};

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
                final growable = columns.where((c) => !_userWidths.containsKey(c.field) && (weights[c.field] ?? 0) > 0).toList();
                final totalWeight = growable.fold<double>(0.0, (a, c) => a + (weights[c.field] ?? 0));
                if (totalWeight > 0) {
                  for (final c in growable) {
                    widths[c.field] = widths[c.field]! + extra * ((weights[c.field] ?? 0) / totalWeight);
                  }
                } else {
                  widths[columns.last.field] = widths[columns.last.field]! + extra;
                }
              }
            }

            final gridColumns = columns.map((col) => GridColumn(
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
            )).toList();

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
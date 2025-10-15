// lib/ui/pretty_data_table.dart
import 'package:flutter/material.dart';

class PrettyDataTable extends StatefulWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double? dataRowMinHeight;
  final double? headingRowHeight;

  const PrettyDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.dataRowMinHeight,
    this.headingRowHeight,
  });

  @override
  State<PrettyDataTable> createState() => _PrettyDataTableState();
}

class _PrettyDataTableState extends State<PrettyDataTable> {
  // Controllers fix: attach to Scrollbar AND the ScrollViews
  final _hCtrl = ScrollController();
  final _vCtrl = ScrollController();

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DataTableTheme(
      data: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(cs.primaryContainer),
        headingTextStyle: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
        dataRowMinHeight: widget.dataRowMinHeight ?? 40,
        headingRowHeight: widget.headingRowHeight ?? 44,
        dividerThickness: 1,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _hCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _hCtrl,
              primary: false,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Scrollbar(
                  controller: _vCtrl,
                  thumbVisibility: true,
                  notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                  child: SingleChildScrollView(
                    controller: _vCtrl,
                    primary: false,
                    scrollDirection: Axis.vertical,
                    child: DataTable(
                      // small bump reduces cramped look when stretching
                      columnSpacing: 28,
                      columns: widget.columns,
                      rows: widget.rows,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Alternating row colors
List<DataRow> withStripedRows(BuildContext context, List<DataRow> baseRows) {
  final cs = Theme.of(context).colorScheme;
  final even = cs.surfaceContainerHighest.withOpacity(0.40);
  final odd = cs.surfaceContainerHighest.withOpacity(0.10);

  return List.generate(baseRows.length, (i) {
    final r = baseRows[i];
    return DataRow(
      color: WidgetStatePropertyAll(i.isEven ? even : odd),
      cells: r.cells,
      onSelectChanged: r.onSelectChanged,
    );
  });
}

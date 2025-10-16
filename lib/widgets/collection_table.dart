import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../data/firestore_streams.dart';
import '../models/columns.dart';
import '../ui/editable_cell.dart';
import '../ui/pretty_data_table.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class CollectionTable extends StatefulWidget {
  final String collection;
  final List<ColumnSpec> columns;
  final String searchQuery;

  const CollectionTable({super.key, required this.collection, required this.columns, this.searchQuery = ''});

  @override
  State<CollectionTable> createState() => _CollectionTableState();
}

class _CollectionTableState extends State<CollectionTable> {
  // Stable keys per (docId, field)
  final Map<String, GlobalKey<EditableCellState>> _cellKeys = {};

  GlobalKey<EditableCellState> _keyFor(String docId, String field) {
    final k = '$docId::$field';
    return _cellKeys.putIfAbsent(k, () => GlobalKey<EditableCellState>());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Doc>>(
      stream: collectionStream(widget.collection),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = (snap.data ?? []);
        final filtered = _filter(docs, widget.searchQuery);

        final dataColumns = widget.columns.map((c) => DataColumn(label: Text(c.label))).toList();
        final dataRows = filtered.map((d) => _buildRow(context, d)).toList();

        return PrettyDataTable(columns: dataColumns, rows: withStripedRows(context, dataRows));
      },
    );
  }

  List<Doc> _filter(List<Doc> docs, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return docs;
    return docs.where((d) {
      final m = d.data();
      return m.values.any((v) => v.toString().toLowerCase().contains(s));
    }).toList();
  }

  DataRow _buildRow(BuildContext context, Doc doc) {
    final m = doc.data();

    DataCell roText(String field, {bool capitalize = false}) {
      final text = (m[field]?.toString() ?? '');
      return DataCell(
        SizedBox(
          width: double.infinity,
          child: Text(
            text.isEmpty ? '' : (capitalize ? text : text),
            style:
                text.isEmpty
                    ? Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
                    : null,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    DataCell editableText(String field, {bool capitalize = false}) {
      final key = _keyFor(doc.id, field);
      final text = (m[field]?.toString() ?? '');
      final cell = EditableCell(
        key: key,
        initial: text,
        capitalize: capitalize,
        onSave: (nv) => doc.reference.update({field: nv}),
      );
      return DataCell(cell, onDoubleTap: () => key.currentState?.beginEdit());
    }

    DataCell editableInt(String field) {
      final key = _keyFor(doc.id, field);
      final text = (m[field]?.toString() ?? '');
      final cell = EditableCell(
        key: key,
        initial: text,
        numbersOnly: true,
        allowDecimal: false,
        allowNegative: true,
        keyboardType: TextInputType.number,
        onSave: (nv) => doc.reference.update({field: int.tryParse(nv) ?? 0}),
      );
      return DataCell(cell, onDoubleTap: () => key.currentState?.beginEdit());
    }

    DataCell editableDec(String field) {
      final key = _keyFor(doc.id, field);
      final text = (m[field]?.toString() ?? '');
      final cell = EditableCell(
        key: key,
        initial: text,
        numbersOnly: true,
        allowDecimal: true,
        allowNegative: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        onSave: (nv) => doc.reference.update({field: double.tryParse(nv) ?? 0}),
      );
      return DataCell(cell, onDoubleTap: () => key.currentState?.beginEdit());
    }

    final cells =
        widget.columns.map((col) {
          switch (col.kind) {
            case CellKind.text:
              return col.editable
                  ? editableText(col.field, capitalize: col.capitalize)
                  : roText(col.field, capitalize: col.capitalize);
            case CellKind.integer:
              return col.editable ? editableInt(col.field) : roText(col.field);
            case CellKind.decimal:
              return col.editable ? editableDec(col.field) : roText(col.field);
            case CellKind.url:
              return col.editable ? editableText(col.field) : roText(col.field);
          }
        }).toList();

    return DataRow(cells: cells);
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/columns.dart';
import '../widgets/collection_table.dart';

class FullList extends StatefulWidget {
  const FullList({super.key});
  @override
  State<FullList> createState() => _FullListState();
}

class _FullListState extends State<FullList> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _uploadCSV() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'tsv']);
    if (result == null || result.files.single.path == null) return;

    final input = File(result.files.single.path!).openRead().transform(utf8.decoder);
    final rows = await input.transform(const CsvToListConverter(shouldParseNumbers: false)).toList();
    if (rows.isEmpty) return;

    final headers = rows.first.map((e) => e.toString().trim()).toList();

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final docData = <String, dynamic>{
        for (var j = 0; j < headers.length && j < row.length; j++) headers[j]: row[j].toString().trim(),
      };

      final category = docData.remove('Type') ?? 'misc_parts';
      final collRef = FirebaseFirestore.instance.collection(category);

      QuerySnapshot dupQuery;
      if (category == 'components') {
        final pt = docData['part_type']?.toString() ?? '';
        final sz = docData['size']?.toString() ?? '';
        final val = docData['value']?.toString() ?? '';
        dupQuery =
            await collRef
                .where('part_type', isEqualTo: pt)
                .where('size', isEqualTo: sz)
                .where('value', isEqualTo: val)
                .get();
      } else {
        final partNum = docData['part_#']?.toString() ?? '';
        dupQuery = await collRef.where('part_#', isEqualTo: partNum).get();
      }

      if (dupQuery.docs.isNotEmpty) {
        final existingDoc = dupQuery.docs.first;
        final existingQty = existingDoc.get('qty') ?? 0;
        final newQty = (int.tryParse(docData['qty']?.toString() ?? '') ?? 0);

        final choice = await showDialog<String>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Duplicate Item Found'),
                content: Text(
                  category == 'components'
                      ? 'Component "${docData['part_type']} ${docData['size']}/${docData['value']}" already has quantity $existingQty.\nWhat do you want to do?'
                      : 'IC "${docData['part_#']}" already has quantity $existingQty.\nWhat do you want to do?',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Skip')),
                  TextButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Replace')),
                  TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('Add')),
                ],
              ),
        );

        if (choice == 'add') {
          await existingDoc.reference.update({'qty': FieldValue.increment(newQty)});
        } else if (choice == 'replace') {
          await existingDoc.reference.update({'qty': newQty});
        } else if (choice == 'cancel') {
          break;
        }
      } else {
        await collRef.add(docData);
      }
    }
  }

  // Column configs per tab
  List<ColumnSpec> get _componentsCols => const [
    ColumnSpec(label: 'Part Type', field: 'part_type', capitalize: true, editable: true),
    ColumnSpec(label: 'Size', field: 'size', editable: true),
    ColumnSpec(label: 'Value', field: 'value', editable: true),
    ColumnSpec(label: 'Qty', field: 'qty', editable: true, kind: CellKind.integer),
    ColumnSpec(label: 'Location', field: 'location', editable: true, kind: CellKind.text),
    ColumnSpec(label: 'Notes', field: 'notes', editable: true, kind: CellKind.text),
  ];

  List<ColumnSpec> get _icsCols => const [
    ColumnSpec(label: 'Part #', field: 'part_#', editable: true),
    ColumnSpec(label: 'Description', field: 'description', editable: true),
    ColumnSpec(label: 'Qty', field: 'qty', editable: true, kind: CellKind.integer),
    ColumnSpec(label: 'Location', field: 'location', editable: true, kind: CellKind.text),
    ColumnSpec(label: 'Notes', field: 'notes', editable: true, kind: CellKind.text),
    ColumnSpec(label: 'Datasheet', field: 'datasheet', editable: true, kind: CellKind.url, maxPercentWidth: 70),
  ];

  List<ColumnSpec> get _connectorsCols => const [
    ColumnSpec(label: 'Part #', field: 'part_#', editable: true),
    ColumnSpec(label: 'Description', field: 'description', editable: true),
    ColumnSpec(label: 'Qty', field: 'qty', editable: true, kind: CellKind.integer),
    ColumnSpec(label: 'Location', field: 'location', editable: true, kind: CellKind.text),
    ColumnSpec(label: 'Notes', field: 'notes', editable: true, kind: CellKind.text),
  ];

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        decoration: InputDecoration(
          labelText: 'Search inventory',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory Viewer'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Components'), Tab(text: 'ICs'), Tab(text: 'Connectors')],
          ),
          actions: [IconButton(icon: const Icon(Icons.upload_file), onPressed: _uploadCSV, tooltip: 'Import CSV')],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  _buildSearchBar(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        CollectionTable(collection: 'components', columns: _componentsCols, searchQuery: _searchQuery),
                        CollectionTable(collection: 'ics', columns: _icsCols, searchQuery: _searchQuery),
                        CollectionTable(collection: 'connectors', columns: _connectorsCols, searchQuery: _searchQuery),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:async/async.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:csv/csv.dart';

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

class FullList extends StatefulWidget {
  const FullList({super.key});

  @override
  _FullListState createState() => _FullListState();
}

class _FullListState extends State<FullList>
    with SingleTickerProviderStateMixin {
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
    // 1) pick & parse CSV just like before…
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'tsv'],
    );
    if (result == null || result.files.single.path == null) return;

    final input = File(
      result.files.single.path!,
    ).openRead().transform(utf8.decoder);

    final rows =
        await input
            .transform(
              const CsvToListConverter(
                fieldDelimiter: ',',
                textDelimiter: '"',
                eol: '\n',
                shouldParseNumbers: false,
              ),
            )
            .toList();

    if (rows.isEmpty) return;
    final headers = rows.first.map((e) => e.toString().trim()).toList();

    // 2) for each data‑row, either add new or update existing…
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final docData = <String, dynamic>{
        for (var j = 0; j < headers.length && j < row.length; j++)
          headers[j]: row[j].toString().trim(),
      };

      final category = docData.remove('Type') ?? 'misc_parts';
      final collRef = FirebaseFirestore.instance.collection(category);

      // 1) Build the duplicate query
      QuerySnapshot dupQuery;
      if (category == 'components') {
        // match on part_type, size, and value
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
        // everything else uses part_#
        final partNum = docData['part_#']?.toString() ?? '';
        dupQuery = await collRef.where('part_#', isEqualTo: partNum).get();
      }

      // 2) If we found a match, prompt the user
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
                      ? 'Component "${docData['part_type']} ${docData['size']}/${docData['value']}" '
                          'already has quantity $existingQty.\nWhat do you want to do?'
                      : 'IC "${docData['part_#']}" already has quantity $existingQty.\nWhat do you want to do?',
                ),
                actions: [
                  TextButton(
                    child: const Text("Cancel"),
                    onPressed: () => Navigator.pop(ctx, 'cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'skip'),
                    child: const Text('Skip'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'replace'),
                    child: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'add'),
                    child: const Text('Add'),
                  ),
                ],
              ),
        );

        if (choice == 'add') {
          await existingDoc.reference.update({
            'qty': FieldValue.increment(newQty),
          });
        } else if (choice == 'replace') {
          await existingDoc.reference.update({'qty': newQty});
        } else if (choice == 'cancel') {
          break;
        }
        // skip does nothing
      } else {
        // 3) brand‑new doc: just add it
        await collRef.add(docData);
      }
    }
  }

  Stream<List<QueryDocumentSnapshot>> _streamFor(String collection) {
    return FirebaseFirestore.instance
        .collection(collection)
        .snapshots()
        .map((snap) => snap.docs);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: const InputDecoration(
          labelText: 'Search',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildComponentsTable() {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _streamFor('components'),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data ?? [];
        final filtered =
            docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data.values.any(
                (v) => v.toString().toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              );
            }).toList();

        return SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Part Type')),
              DataColumn(label: Text('Size')),
              DataColumn(label: Text('Value')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Notes')),
            ],
            rows:
                filtered.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          (data['part_type'] as String?)?.capitalize() ?? '',
                        ),
                      ),
                      DataCell(Text(data['size']?.toString() ?? '')),
                      DataCell(Text(data['value']?.toString() ?? '')),
                      DataCell(Text(data['qty']?.toString() ?? '')),
                      DataCell(Text(data['location'] ?? '')),
                      DataCell(Text(data['notes'] ?? '')),
                    ],
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildIcsTable() {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _streamFor('ics'),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data ?? [];
        final filtered =
            docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data.values.any(
                (v) => v.toString().toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              );
            }).toList();

        return SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Part #')),
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Datasheet')),
              DataColumn(label: Text('Notes')),
            ],
            rows:
                filtered.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DataRow(
                    cells: [
                      DataCell(Text(data['part_#']?.toString() ?? '')),
                      DataCell(Text(data['description']?.toString() ?? '')),
                      DataCell(Text(data['qty']?.toString() ?? '')),
                      DataCell(Text(data['location']?.toString() ?? '')),
                      DataCell(Text(data['datasheet']?.toString() ?? '')),
                      DataCell(Text(data['notes']?.toString() ?? '')),
                    ],
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildConnectorsTable() {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _streamFor('connectors'),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data ?? [];
        final filtered =
            docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data.values.any(
                (v) => v.toString().toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              );
            }).toList();

        return SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Part #')),
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Notes')),
            ],
            rows:
                filtered.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DataRow(
                    cells: [
                      DataCell(Text(data['part_#']?.toString() ?? '')),
                      DataCell(Text(data['description']?.toString() ?? '')),
                      DataCell(Text(data['qty']?.toString() ?? '')),
                      DataCell(Text(data['location']?.toString() ?? '')),
                      DataCell(Text(data['notes']?.toString() ?? '')),
                    ],
                  );
                }).toList(),
          ),
        );
      },
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
            tabs: const [
              Tab(text: 'Components'),
              Tab(text: 'ICs'),
              Tab(text: 'Connectors'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _uploadCSV,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildComponentsTable(),
                  _buildIcsTable(),
                  _buildConnectorsTable(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

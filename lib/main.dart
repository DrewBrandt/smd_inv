import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:async/async.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventory Viewer',
      theme: ThemeData.dark(),
      home: InventoryHome(),
    );
  }
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({super.key});

  @override
  _InventoryHomeState createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome> {
  final List<String> _collections = ['components', 'ics', 'misc_parts'];
  final Set<String> _selectedCollections = {'components', 'ics', 'misc_parts'};
  String _searchQuery = '';

  void _uploadCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result != null && result.files.single.bytes != null) {
      final fileBytes = result.files.single.bytes!;
      final content = utf8.decode(fileBytes);
      final lines = const LineSplitter().convert(content);
      final headers = lines.first.split(',');

      for (var i = 1; i < lines.length; i++) {
        final values = lines[i].split(',');
        final Map<String, dynamic> doc = {
          for (int j = 0; j < headers.length; j++)
            headers[j].trim(): values[j].trim(),
        };
        final category = doc.remove('category') ?? 'misc_parts';
        await FirebaseFirestore.instance.collection(category).add(doc);
      }
    }
  }

  Stream<List<QueryDocumentSnapshot>> _filteredDocuments() {
    final streams = _selectedCollections.map((collection) {
      return FirebaseFirestore.instance
          .collection(collection)
          .snapshots()
          .map((snap) => snap.docs);
    });
    return Stream<List<QueryDocumentSnapshot>>.multi((controller) async {
      await for (final snapshots in StreamZip(streams)) {
        final merged = snapshots.expand((e) => e).toList();
        controller.add(merged);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _uploadCSV,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Search'),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: null,
                    hint: const Text('Filter types'),
                    items:
                        _collections.map((collection) {
                          final selected = _selectedCollections.contains(
                            collection,
                          );
                          return DropdownMenuItem<String>(
                            value: collection,
                            child: Row(
                              children: [
                                Checkbox(
                                  value: selected,
                                  onChanged:
                                      (_) => setState(() {
                                        if (selected) {
                                          _selectedCollections.remove(
                                            collection,
                                          );
                                        } else {
                                          _selectedCollections.add(collection);
                                        }
                                      }),
                                ),
                                Text(collection),
                              ],
                            ),
                          );
                        }).toList(),
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
              stream: _filteredDocuments(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                final docs = snapshot.data ?? [];
                final filteredDocs =
                    docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data.values.any(
                        (v) => v.toString().toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ),
                      );
                    }).toList();

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Part Type')),
                      DataColumn(label: Text('Qty')),
                      DataColumn(label: Text('Location')),
                      DataColumn(label: Text('Notes')),
                    ],
                    rows:
                        filteredDocs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(data['part_type'] ?? data['name'] ?? ''),
                              ),
                              DataCell(Text(data['qty']?.toString() ?? '')),
                              DataCell(Text(data['location'] ?? '')),
                              DataCell(Text(data['notes'] ?? '')),
                            ],
                          );
                        }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

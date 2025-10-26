// lib/widgets/bom_import_dialog.dart
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class BomImportDialog extends StatefulWidget {
  const BomImportDialog({super.key});

  @override
  State<BomImportDialog> createState() => _BomImportDialogState();
}

class _BomImportDialogState extends State<BomImportDialog> {
  List<Map<String, dynamic>>? _parsedBom;
  bool _isLoading = false;
  bool _isMatching = false;
  String? _error;
  bool _showPasteMode = false;
  final _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickAndParseCSV() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'tsv']);

      if (result == null || result.files.single.path == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = File(result.files.single.path!);
      final input = file.openRead().transform(utf8.decoder);
      final rows = await input.transform(const CsvToListConverter(shouldParseNumbers: false)).toList();

      if (rows.isEmpty) {
        setState(() {
          _error = 'CSV file is empty';
          _isLoading = false;
        });
        return;
      }

      await _parseBOM(rows);
    } catch (e) {
      setState(() {
        _error = 'Error reading CSV: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _parsePastedData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final text = _pasteController.text.trim();
      if (text.isEmpty) {
        setState(() {
          _error = 'Please paste BOM data';
          _isLoading = false;
        });
        return;
      }

      final hasTab = text.contains('\t');
      final converter = CsvToListConverter(eol: '\n', fieldDelimiter: hasTab ? '\t' : ',', shouldParseNumbers: false);

      final rows = converter.convert(text);
      if (rows.isEmpty) {
        setState(() {
          _error = 'No data found in pasted text';
          _isLoading = false;
        });
        return;
      }

      await _parseBOM(rows);
      setState(() => _showPasteMode = false);
    } catch (e) {
      setState(() {
        _error = 'Error parsing data: $e';
        _isLoading = false;
      });
    }
  }

  String _normalizeValue(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();

    // Unify µ → u, remove spaces
    s = s.replaceAll('µ', 'u').replaceAll(RegExp(r'\s+'), '');

    // Drop trailing unit markers like 'uf', 'nf', 'pf' → keep just u/n/p
    s = s.replaceAll(RegExp(r'([unpkmM])f$'), r'$1');

    // “Embedded unit as decimal separator” forms:
    //  e.g., 2u2 → 2.2u, 100n0 → 100n
    final m = RegExp(r'^(\d+)([unpkmMG])(\d+)$').firstMatch(s);
    if (m != null) {
      final intPart = m.group(1)!;
      final unit = m.group(2)!;
      final frac = m.group(3)!;
      if (RegExp(r'^0+$').hasMatch(frac)) {
        return '$intPart$unit'; // e.g., 100n0 → 100n
      } else {
        return '$intPart.$frac$unit'; // e.g., 2u2 → 2.2u
      }
    }

    // Already decimal + unit (e.g., 2.2uF) → 2.2u handled above by removing 'f'
    return s;
  }

  Future<void> _parseBOM(List<List> rows) async {
    final headers = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    final parsed = <Map<String, dynamic>>[];

    // Find column indices (KiCad typical format)
    final refIdx = headers.indexWhere((h) => h.contains('ref') || h.contains('designator'));
    final qtyIdx = headers.indexWhere((h) => h.contains('qty') || h.contains('quantity'));
    final valueIdx = headers.indexWhere((h) => h.contains('val') && !h.contains('eval'));
    final footprintIdx = headers.indexWhere((h) => h.contains('footprint') || h.contains('package'));

    if (refIdx == -1 || qtyIdx == -1) {
      setState(() {
        _error = 'Could not find Reference and Quantity columns';
        _isLoading = false;
      });
      return;
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= refIdx || row.length <= qtyIdx) continue;

      final designators = row[refIdx].toString().trim();
      final qty = int.tryParse(row[qtyIdx].toString()) ?? 1;
      final value = valueIdx >= 0 && row.length > valueIdx ? _normalizeValue(row[valueIdx].toString()) : '';
      final footprint = footprintIdx >= 0 && row.length > footprintIdx ? row[footprintIdx].toString().trim() : '';
      final partNum = valueIdx >= 0 && row.length > valueIdx ? row[valueIdx].toString().trim() : '';

      if (designators.isEmpty) continue;

      // Detect component type
      final ref = designators.split(',').first.trim();
      String category = 'components';
      String partType = '';

      if (ref.startsWith('C')) {
        partType = 'capacitor';
      } else if (ref.startsWith('R')) {
        partType = 'resistor';
      } else if (ref.startsWith('L')) {
        partType = 'inductor';
      } else if (ref.startsWith('D')) {
        partType = 'diode';
      } else if (ref.startsWith('U') || ref.startsWith('Q') || ref.startsWith('IC')) {
        category = 'ics';
        partType = 'ic';
      } else if (ref.startsWith('J') || ref.startsWith('P') || ref.startsWith('X')) {
        category = 'connectors';
        partType = 'connector';
      }

      // Extract package size from footprint
      String size = '';
      final sizeMatch = RegExp(r'(0201|0402|0603|0805|1206|1210|2512)').firstMatch(footprint);
      if (sizeMatch != null) {
        size = sizeMatch.group(0)!;
      }

      parsed.add({
        'designators': designators,
        'qty': qty,
        'notes': '',
        'description': '',
        'category': category,
        'required_attributes': {
          'part_type': partType,
          'value': value,
          'size': size,
          'part_#': partNum,
          'selected_component_ref': null,
        },
        'inventory_match': null, // Will be populated by matching
        'match_status': 'pending', // pending, matched, multiple, missing
      });
    }

    setState(() {
      _parsedBom = parsed;
      _isLoading = false;
    });

    // Auto-match with inventory
    await _matchInventory();
  }

  Future<void> _matchInventory() async {
    if (_parsedBom == null) return;

    setState(() => _isMatching = true);

    try {
      final inventory = await FirebaseFirestore.instance.collection('inventory').get();

      for (final line in _parsedBom!) {
        final attrs = line['required_attributes'] as Map<String, dynamic>;
        final partNum = attrs['part_#']?.toString() ?? '';
        final value = attrs['value']?.toString() ?? '';
        final size = attrs['size']?.toString() ?? '';
        final partType = attrs['part_type']?.toString() ?? '';

        // Find matches
        List<QueryDocumentSnapshot> matches = [];

        if (partNum.isNotEmpty) {
          // Match by part number (most specific)
          matches =
              inventory.docs.where((doc) {
                final data = doc.data();
                return partNum.contains(data['part_#']?.toString() ?? '');
              }).toList();
        } else if (partType == 'capacitor' || partType == 'resistor' || partType == 'inductor' || partType == 'diode') {
          // Match passives by type + value + size
          matches =
              inventory.docs.where((doc) {
                final data = doc.data();
                return data['type']?.toString() == partType &&
                    data['value']?.toString() == value &&
                    data['package']?.toString() == size;
              }).toList();
        }

        if (matches.isEmpty) {
          line['match_status'] = 'missing';
        } else if (matches.length == 1) {
          line['match_status'] = 'matched';
          line['inventory_match'] = {
            'doc_id': matches.first.id,
            'part_#': (matches.first.data() as Map<String, dynamic>)['part_#'],
            'available_qty': (matches.first.data() as Map<String, dynamic>)['qty'],
          };
          attrs['selected_component_ref'] = matches.first.id;
        } else {
          line['match_status'] = 'multiple';
          line['inventory_matches'] =
              matches
                  .map(
                    (m) => {
                      'doc_id': m.id,
                      'part_#': (m.data() as Map<String, dynamic>)['part_#'],
                      'description': (m.data() as Map<String, dynamic>)['description'],
                      'available_qty': (m.data() as Map<String, dynamic>)['qty'],
                    },
                  )
                  .toList();
        }
      }

      setState(() => _isMatching = false);
    } catch (e) {
      setState(() {
        _error = 'Error matching inventory: $e';
        _isMatching = false;
      });
    }
  }

  Future<void> _resolveMatch(int lineIndex, String docId) async {
    final line = _parsedBom![lineIndex];
    final doc = await FirebaseFirestore.instance.collection('inventory').doc(docId).get();

    setState(() {
      line['match_status'] = 'matched';
      line['inventory_match'] = {
        'doc_id': doc.id,
        'part_#': doc.data()!['part_#'],
        'available_qty': doc.data()!['qty'],
      };
      line['required_attributes']['selected_component_ref'] = doc.id;
      line.remove('inventory_matches');
    });
  }

  Widget _buildMatchIndicator(String status) {
    switch (status) {
      case 'matched':
        return const Tooltip(
          message: 'Matched to inventory',
          child: Icon(Icons.check_circle, color: Colors.green, size: 20),
        );
      case 'multiple':
        return const Tooltip(
          message: 'Multiple matches - click to choose',
          child: Icon(Icons.warning, color: Colors.orange, size: 20),
        );
      case 'missing':
        return const Tooltip(message: 'Not in inventory', child: Icon(Icons.error, color: Colors.red, size: 20));
      default:
        return const SizedBox(width: 20);
    }
  }

  Future<void> _showInventorySearchDialog(int lineIndex) async {
    final line = _parsedBom![lineIndex];
    final attrs = line['required_attributes'] as Map<String, dynamic>;

    String searchQuery = [
      attrs['part_type'],
      attrs['value'],
      attrs['size'],
    ].where((s) => s != null && s.toString().isNotEmpty).join(' ');

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => _InventorySearchDialog(initialQuery: searchQuery),
    );

    if (chosen != null) {
      await _resolveMatch(lineIndex, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Text('Import BOM', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),

              // Content
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))))
              else if (_parsedBom == null)
                Expanded(
                  child:
                      _showPasteMode
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Paste KiCad BOM data:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text(
                                'Must include Reference and Quantity columns',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: TextField(
                                  controller: _pasteController,
                                  maxLines: null,
                                  expands: true,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'Paste your BOM data here...',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => setState(() => _showPasteMode = false),
                                    child: const Text('Back'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: _parsePastedData,
                                    icon: const Icon(Icons.check),
                                    label: const Text('Parse BOM'),
                                  ),
                                ],
                              ),
                            ],
                          )
                          : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.upload_file, size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                const Text('Import Bill of Materials from KiCad'),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: _pickAndParseCSV,
                                  icon: const Icon(Icons.file_open),
                                  label: const Text('Choose CSV File'),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () => setState(() => _showPasteMode = true),
                                  icon: const Icon(Icons.content_paste),
                                  label: const Text('Paste BOM Data'),
                                ),
                              ],
                            ),
                          ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isMatching)
                        const LinearProgressIndicator()
                      else
                        Row(
                          children: [
                            Text('${_parsedBom!.length} lines parsed'),
                            const SizedBox(width: 16),
                            Text(
                              '${_parsedBom!.where((l) => l['match_status'] == 'matched').length} matched',
                              style: const TextStyle(color: Colors.green),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_parsedBom!.where((l) => l['match_status'] == 'multiple').length} ambiguous',
                              style: const TextStyle(color: Colors.orange),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_parsedBom!.where((l) => l['match_status'] == 'missing').length} missing',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _parsedBom!.length,
                          itemBuilder: (context, i) {
                            final line = _parsedBom![i];
                            final attrs = line['required_attributes'] as Map<String, dynamic>;
                            final status = line['match_status'];
                            final footprint = line['footprint']?.toString() ?? '';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: _buildMatchIndicator(status),
                                title: Text('${line['designators']} (${line['qty']}×)'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      [
                                        attrs['part_type'],
                                        attrs['value'],
                                        attrs['size'],
                                        if (attrs['size']?.toString().isEmpty ?? true)
                                          '(from: ${footprint.split(':').last.split('_').where((p) => p.contains('0') || p.contains('1') || p.contains('2')).firstOrNull ?? ""})',
                                      ].where((s) => s != null && s.toString().isNotEmpty).join(' • '),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    if (status == 'matched')
                                      Text(
                                        '✓ Matched: ${line['inventory_match']['part_#']} (${line['inventory_match']['available_qty']} available)',
                                        style: const TextStyle(fontSize: 11, color: Colors.green),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (status == 'missing' || status == 'multiple')
                                      IconButton(
                                        icon: const Icon(Icons.search, size: 20),
                                        tooltip: 'Search inventory',
                                        onPressed: () => _showInventorySearchDialog(i),
                                      ),
                                    if (status == 'multiple')
                                      TextButton(
                                        onPressed: () async {
                                          final matches = line['inventory_matches'] as List;
                                          final chosen = await showDialog<String>(
                                            context: context,
                                            builder:
                                                (ctx) => AlertDialog(
                                                  title: const Text('Choose Match'),
                                                  content: SizedBox(
                                                    width: 400,
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children:
                                                          matches.map<Widget>((m) {
                                                            return ListTile(
                                                              title: Text(m['part_#']),
                                                              subtitle: Text(
                                                                '${m['description']} (${m['available_qty']} avail)',
                                                              ),
                                                              onTap: () => Navigator.pop(ctx, m['doc_id']),
                                                            );
                                                          }).toList(),
                                                    ),
                                                  ),
                                                ),
                                          );
                                          if (chosen != null) {
                                            await _resolveMatch(i, chosen);
                                          }
                                        },
                                        child: const Text('Choose'),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_parsedBom != null) ...[
                    TextButton(
                      onPressed: () => setState(() => _parsedBom = null),
                      child: const Text('Choose Different File'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  if (_parsedBom != null)
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _parsedBom),
                      icon: const Icon(Icons.check),
                      label: Text('Import ${_parsedBom!.length} Lines'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Inventory search dialog widget
class _InventorySearchDialog extends StatefulWidget {
  final String initialQuery;

  const _InventorySearchDialog({required this.initialQuery});

  @override
  State<_InventorySearchDialog> createState() => _InventorySearchDialogState();
}

class _InventorySearchDialogState extends State<_InventorySearchDialog> {
  String _searchQuery = '';
  List<QueryDocumentSnapshot>? _results;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialQuery;
    _search();
  }

  Future<void> _search() async {
    setState(() => _isSearching = true);

    final inventory = await FirebaseFirestore.instance.collection('inventory').get();
    final query = _searchQuery.toLowerCase();

    final filtered =
        inventory.docs.where((doc) {
          final data = doc.data();
          final searchable =
              [
                data['part_#'],
                data['type'],
                data['value'],
                data['package'],
                data['description'],
              ].join(' ').toLowerCase();
          return searchable.contains(query);
        }).toList();

    setState(() {
      _results = filtered;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Inventory'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _searchQuery),
              onChanged: (v) => _searchQuery = v,
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_results == null)
              const Expanded(child: Center(child: Text('Enter search terms')))
            else if (_results!.isEmpty)
              const Expanded(child: Center(child: Text('No matches found')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results!.length,
                  itemBuilder: (context, i) {
                    final doc = _results![i];
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data['part_#'] ?? ''),
                      subtitle: Text(
                        [
                          data['type'],
                          data['value'],
                          data['package'],
                          '(${data['qty']} avail)',
                        ].where((s) => s != null && s.toString().isNotEmpty).join(' • '),
                      ),
                      onTap: () => Navigator.pop(context, doc.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _search, child: const Text('Search')),
      ],
    );
  }
}

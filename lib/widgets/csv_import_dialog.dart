// lib/widgets/csv_import_dialog.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/models/columns.dart';
import 'package:smd_inv/services/csv_parser_service.dart';
import 'package:smd_inv/widgets/collection_datagrid.dart';

class CSVImportDialog extends StatefulWidget {
  const CSVImportDialog({super.key});

  @override
  State<CSVImportDialog> createState() => _CSVImportDialogState();
}

class _CSVImportDialogState extends State<CSVImportDialog> {
  List<Map<String, dynamic>>? _parsedRows;
  bool _isLoading = false;
  bool _isImporting = false;
  String? _error;
  bool _showPasteMode = false;

  String _defaultLocation = '';
  String _defaultPackage = '0603';
  final _pasteController = TextEditingController();

  Future<void> _pickAndParseCSV() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Use CsvParserService for consistent parsing
      final parseResult = await CsvParserService.parseFromFile(
        expectedColumns: ['Item', 'Quantity', 'Link', 'Notes', 'Price Per Unit'],
      );

      if (!parseResult.success) {
        setState(() {
          _error = parseResult.error ?? 'Failed to parse CSV';
          _isLoading = false;
        });
        return;
      }

      if (parseResult.dataRows.isEmpty) {
        setState(() {
          _error = 'CSV file is empty';
          _isLoading = false;
        });
        return;
      }

      // Convert parsed rows to inventory items
      final items = <Map<String, dynamic>>[];
      for (final row in parseResult.dataRows) {
        final item = _parseItemFromParsedRow(parseResult, row);
        if (item != null) items.add(item);
      }

      setState(() {
        _parsedRows = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error reading CSV: $e';
        _isLoading = false;
      });
    }
  }

  /// Parse a single row from CsvParseResult into inventory item format
  Map<String, dynamic>? _parseItemFromParsedRow(
    CsvParseResult parseResult,
    List<dynamic> row,
  ) {
    final itemName = parseResult.getCellValue(row, 'Item');
    if (itemName.isEmpty) return null;

    final qty = int.tryParse(parseResult.getCellValue(row, 'Quantity')) ?? 0;
    final link = parseResult.getCellValue(row, 'Link');
    final notes = parseResult.getCellValue(row, 'Notes');

    // Parse price
    final priceStr = parseResult.getCellValue(row, 'Price Per Unit');
    double? pricePerUnit;
    if (priceStr.isNotEmpty) {
      // Remove $ and parse
      final cleaned = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
      pricePerUnit = double.tryParse(cleaned);
    }

    return _buildInventoryItem(itemName, qty, link, notes, pricePerUnit);
  }

  /// Build inventory item map from parsed CSV data
  Map<String, dynamic> _buildInventoryItem(
    String itemName,
    int qty,
    String link,
    String notes,
    double? pricePerUnit,
  ) {

    // Extract part# from DigiKey URL
    String partNumber = '';
    if (link.contains('digikey.com')) {
      final match = RegExp(r'/detail/[^/]+/([^/]+)/').firstMatch(link);
      if (match != null) {
        partNumber = match.group(1)!;
      }
    }

    // Detect type and parse accordingly
    final itemLower = itemName.toLowerCase();

    // Passives (capacitors, resistors, inductors)
    if (itemLower.contains('cap') || itemLower.contains('uf')) {
      final value = _extractValue(itemName);
      return {
        'part_#': partNumber.isNotEmpty ? partNumber : 'CAP-$_defaultPackage-${value ?? "UNKNOWN"}',
        'type': 'capacitor',
        'value': value,
        'package': _defaultPackage,
        'description': itemName,
        'qty': qty,
        'location': _defaultLocation,
        'notes': notes,
        'vendor_link': link,
        'price_per_unit': pricePerUnit,
        'datasheet': link,
      };
    }

    if (itemLower.contains('resistor') || itemLower.contains('ohm')) {
      final value = _extractValue(itemName);
      return {
        'part_#': partNumber.isNotEmpty ? partNumber : 'RES-$_defaultPackage-${value ?? "UNKNOWN"}',
        'type': 'resistor',
        'value': value,
        'package': _defaultPackage,
        'description': itemName,
        'qty': qty,
        'location': _defaultLocation,
        'notes': notes,
        'vendor_link': link,
        'price_per_unit': pricePerUnit,
        'datasheet': link,
      };
    }

    // Connectors
    if (itemLower.contains('jst') ||
        itemLower.contains('connector') ||
        itemLower.contains('pin male') ||
        itemLower.contains('pin female')) {
      return {
        'part_#': partNumber.isNotEmpty ? partNumber : itemName,
        'type': 'connector',
        'value': null,
        'package': _extractPackage(itemName) ?? '',
        'description': itemName,
        'qty': qty,
        'location': _defaultLocation,
        'notes': notes,
        'vendor_link': link,
        'price_per_unit': pricePerUnit,
        'datasheet': null,
      };
    }

    // Default to IC
    return {
      'part_#': partNumber.isNotEmpty ? partNumber : itemName,
      'type': 'ic',
      'value': null,
      'package': _extractPackage(itemName) ?? '',
      'description': itemName,
      'qty': qty,
      'location': _defaultLocation,
      'notes': notes,
      'vendor_link': link,
      'price_per_unit': pricePerUnit,
      'datasheet': link,
    };
  }

  String? _extractValue(String itemName) {
    // Match patterns like "2.2uF", "10k", "100nF"
    final match = RegExp(r'(\d+\.?\d*)\s*(u|n|p|k|m|M|G)?(?:F|H|ohm)?', caseSensitive: false).firstMatch(itemName);

    if (match != null) {
      final num = match.group(1);
      final unit = match.group(2)?.toLowerCase() ?? '';

      // Normalize to standard format
      if (unit.isEmpty) return num;
      return '$num$unit';
    }

    return null;
  }

  String? _extractPackage(String itemName) {
    // Common package patterns
    final patterns = [
      RegExp(r'\b(SOIC|QFP|QFN|DIP|TSSOP|VFQFPN|LQFP|TQFP)-?\d+\b', caseSensitive: false),
      RegExp(r'\bJST[- ]?[A-Z]{2}[- ]?\d+P?\b', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(itemName);
      if (match != null) return match.group(0);
    }

    return null;
  }

  Future<void> _importToFirestore() async {
    if (_parsedRows == null || _parsedRows!.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      int imported = 0;
      int skipped = 0;

      for (final row in _parsedRows!) {
        // Check for duplicates
        final partNum = row['part_#']?.toString() ?? '';
        if (partNum.isEmpty) {
          skipped++;
          continue;
        }

        final existing = await FirebaseFirestore.instance
            .collection(FirestoreCollections.inventory)
            .where(FirestoreFields.partNumber, isEqualTo: partNum)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          // Duplicate found - ask user
          if (!mounted) break;

          final action = await _showDuplicateDialog(row, existing.docs.first.data());

          if (action == null || action == 'cancel') {
            skipped++;
            continue;
          } else if (action == 'add') {
            // Add quantity to existing
            final existingQty = existing.docs.first.data()['qty'] ?? 0;
            final newQty = row['qty'] ?? 0;
            await existing.docs.first.reference.update({
              'qty': existingQty + newQty,
              'last_updated': FieldValue.serverTimestamp(),
            });
            imported++;
          } else if (action == 'replace') {
            // Replace entire document
            await existing.docs.first.reference.set({...row, 'last_updated': FieldValue.serverTimestamp()});
            imported++;
          }
          // 'skip' falls through to skipped++
        } else {
          // New item
          await FirebaseFirestore.instance
              .collection(FirestoreCollections.inventory)
              .add({
            ...row,
            FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
          });
          imported++;
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✅ Imported $imported items${skipped > 0 ? ", skipped $skipped" : ""}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<String?> _showDuplicateDialog(Map<String, dynamic> newItem, Map<String, dynamic> existingItem) async {
    return showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Duplicate Found'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Part #: ${newItem['part_#']}'),
                  const SizedBox(height: 12),
                  Text('Existing qty: ${existingItem['qty']}'),
                  Text('New qty: ${newItem['qty']}'),
                  const SizedBox(height: 12),
                  Text('Existing notes: ${existingItem['notes'] ?? "(none)"}'),
                  Text('New notes: ${newItem['notes'] ?? "(none)"}'),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel Import')),
              TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Skip This')),
              TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: const Text('Add Quantity')),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Replace')),
            ],
          ),
    );
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
          _error = 'Please paste CSV/TSV data';
          _isLoading = false;
        });
        return;
      }

      // Use CsvParserService for consistent parsing
      final parseResult = CsvParserService.parse(
        text,
        expectedColumns: ['Item', 'Quantity', 'Link', 'Notes', 'Price Per Unit'],
      );

      if (!parseResult.success) {
        setState(() {
          _error = parseResult.error ?? 'Failed to parse data';
          _isLoading = false;
        });
        return;
      }

      if (parseResult.dataRows.isEmpty) {
        setState(() {
          _error = 'No data found in pasted text';
          _isLoading = false;
        });
        return;
      }

      // Convert parsed rows to inventory items
      final items = <Map<String, dynamic>>[];
      for (final row in parseResult.dataRows) {
        final item = _parseItemFromParsedRow(parseResult, row);
        if (item != null) items.add(item);
      }

      setState(() {
        _parsedRows = items;
        _isLoading = false;
        _showPasteMode = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error parsing data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
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
                  const Text('Import from CSV', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),

              // Settings row
              if (_parsedRows == null) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Default Location',
                          border: OutlineInputBorder(),
                          hintText: 'e.g., Incoming, Shelf A',
                        ),
                        onChanged: (v) => _defaultLocation = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'Default Package', border: OutlineInputBorder()),
                        controller: TextEditingController(text: _defaultPackage),
                        onChanged: (v) => _defaultPackage = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Content
              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))))
              else if (_parsedRows == null)
                Expanded(
                  child:
                      _showPasteMode
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Paste CSV or TSV data:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text(
                                'Copy data from Excel, Google Sheets, or a text file and paste here.',
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
                                    hintText: 'Paste your data here...',
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
                                    label: const Text('Parse Data'),
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
                                const Text('Import inventory from CSV or TSV'),
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
                                  label: const Text('Paste CSV/TSV Data'),
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
                      Text(
                        'Preview (${_parsedRows!.length} items)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Review and edit items before importing. Double-click cells to edit.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: CollectionDataGrid(
                          rows: _parsedRows,
                          onRowsChanged: (updated) => setState(() => _parsedRows = updated),
                          columns: [
                            ColumnSpec(field: 'part_#', label: 'Part #'),
                            ColumnSpec(field: 'type', label: 'Type'),
                            ColumnSpec(field: 'value', label: 'Value'),
                            ColumnSpec(field: 'package', label: 'Package'),
                            ColumnSpec(field: 'description', label: 'Description'),
                            ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
                            ColumnSpec(field: 'location', label: 'Location'),
                            ColumnSpec(field: 'notes', label: 'Notes'),
                          ],
                          searchQuery: '',
                          persistKey: 'csv_import_preview',
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
                  if (_parsedRows != null) ...[
                    TextButton(
                      onPressed: () => setState(() => _parsedRows = null),
                      child: const Text('Choose Different File'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(
                    onPressed: _isImporting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (_parsedRows != null)
                    FilledButton.icon(
                      onPressed: _isImporting ? null : _importToFirestore,
                      icon:
                          _isImporting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check),
                      label: Text(_isImporting ? 'Importing...' : 'Import ${_parsedRows!.length} Items'),
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

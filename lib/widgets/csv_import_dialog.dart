// lib/widgets/csv_import_dialog.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/models/columns.dart';
import 'package:smd_inv/services/csv_parser_service.dart';
import 'package:smd_inv/services/inventory_csv_mapper.dart';
import 'package:smd_inv/services/inventory_history_service.dart';
import 'package:smd_inv/services/part_normalizer.dart';
import 'package:smd_inv/widgets/unified_data_grid.dart';

class CSVImportDialog extends StatefulWidget {
  final InventoryHistoryService? historyService;

  const CSVImportDialog({super.key, this.historyService});

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
        expectedColumns: InventoryCsvMapper.expectedColumns,
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

      final items = InventoryCsvMapper.toInventoryItems(
        parseResult,
        defaultLocation: _defaultLocation,
        defaultPackage: _defaultPackage,
      );

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

  Future<void> _importToFirestore() async {
    if (_parsedRows == null || _parsedRows!.isEmpty) return;

    setState(() => _isImporting = true);

    try {
      final inventoryCollection = FirebaseFirestore.instance.collection(
        FirestoreCollections.inventory,
      );
      final existingSnapshot = await inventoryCollection.get();
      final existingByPart =
          <
            String,
            ({
              DocumentReference<Map<String, dynamic>> ref,
              Map<String, dynamic> data,
            })
          >{};

      for (final doc in existingSnapshot.docs) {
        final partNum =
            doc.data()[FirestoreFields.partNumber]?.toString() ?? '';
        final canonical = PartNormalizer.canonicalPartNumber(partNum);
        if (canonical.isEmpty || existingByPart.containsKey(canonical)) {
          continue;
        }
        existingByPart[canonical] = (
          ref: doc.reference,
          data: Map<String, dynamic>.from(doc.data()),
        );
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      var pendingWrites = 0;

      Future<void> flushBatch() async {
        if (pendingWrites == 0) return;
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        pendingWrites = 0;
      }

      void queueSet(
        DocumentReference<Map<String, dynamic>> ref,
        Map<String, dynamic> data,
      ) {
        batch.set(ref, data);
        pendingWrites++;
      }

      void queueUpdate(
        DocumentReference<Map<String, dynamic>> ref,
        Map<String, dynamic> data,
      ) {
        batch.update(ref, data);
        pendingWrites++;
      }

      int imported = 0;
      int skipped = 0;
      bool cancelled = false;

      final addedItems = <ImportedItemRecord>[];
      final updatedItems = <UpdatedItemRecord>[];

      for (final row in _parsedRows!) {
        // Check for duplicates
        final partNum = row[FirestoreFields.partNumber]?.toString() ?? '';
        if (partNum.isEmpty) {
          skipped++;
          continue;
        }

        final canonicalPartNum = PartNormalizer.canonicalPartNumber(partNum);
        final existing = existingByPart[canonicalPartNum];

        if (existing != null) {
          // Duplicate found - ask user
          if (!mounted) break;

          final currentSnapshot = Map<String, dynamic>.from(existing.data);
          final action = await _showDuplicateDialog(row, currentSnapshot);

          switch (action) {
            case null:
            case 'cancel':
              cancelled = true;
              break;
            case 'skip':
              skipped++;
              continue;
            case 'add':
              final existingQty =
                  (currentSnapshot[FirestoreFields.qty] as num?)?.toInt() ?? 0;
              final newQty = (row[FirestoreFields.qty] as num?)?.toInt() ?? 0;
              final newSnapshot = {
                ...currentSnapshot,
                FirestoreFields.qty: existingQty + newQty,
              };
              queueUpdate(existing.ref, {
                FirestoreFields.qty: existingQty + newQty,
                FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
              });
              existingByPart[canonicalPartNum] = (
                ref: existing.ref,
                data: newSnapshot,
              );
              updatedItems.add(
                UpdatedItemRecord(
                  docId: existing.ref.id,
                  importAction: 'add_qty',
                  oldSnapshot: currentSnapshot,
                  newSnapshot: newSnapshot,
                ),
              );
              imported++;
              if (pendingWrites >= 400) {
                await flushBatch();
              }
              continue;
            case 'replace':
              final newSnapshot = Map<String, dynamic>.from(row);
              queueSet(existing.ref, {
                ...newSnapshot,
                FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
              });
              existingByPart[canonicalPartNum] = (
                ref: existing.ref,
                data: newSnapshot,
              );
              updatedItems.add(
                UpdatedItemRecord(
                  docId: existing.ref.id,
                  importAction: 'replace',
                  oldSnapshot: currentSnapshot,
                  newSnapshot: newSnapshot,
                ),
              );
              imported++;
              if (pendingWrites >= 400) {
                await flushBatch();
              }
              continue;
          }

          if (cancelled) break;
        } else {
          // New item
          final docRef = inventoryCollection.doc();
          final historySnapshot = Map<String, dynamic>.from(row);
          queueSet(docRef, {
            ...historySnapshot,
            FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
          });
          existingByPart[canonicalPartNum] = (
            ref: docRef,
            data: historySnapshot,
          );
          addedItems.add(
            ImportedItemRecord(docId: docRef.id, snapshot: historySnapshot),
          );
          imported++;
          if (pendingWrites >= 400) {
            await flushBatch();
          }
        }

        if (cancelled) break;
      }

      await flushBatch();

      // Record a single history entry for the entire import batch.
      if (imported > 0) {
        widget.historyService
            ?.recordImport(addedItems: addedItems, updatedItems: updatedItems)
            .catchError((_) {});
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cancelled
                  ? 'Import cancelled after $imported items${skipped > 0 ? ", skipped $skipped" : ""}'
                  : 'Imported $imported items${skipped > 0 ? ", skipped $skipped" : ""}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<String?> _showDuplicateDialog(
    Map<String, dynamic> newItem,
    Map<String, dynamic> existingItem,
  ) async {
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
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel Import'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'skip'),
                child: const Text('Skip This'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'add'),
                child: const Text('Add Quantity'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: const Text('Replace'),
              ),
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
        expectedColumns: InventoryCsvMapper.expectedColumns,
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

      final items = InventoryCsvMapper.toInventoryItems(
        parseResult,
        defaultLocation: _defaultLocation,
        defaultPackage: _defaultPackage,
      );

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
                  const Text(
                    'Import from CSV',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
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
                        decoration: const InputDecoration(
                          labelText: 'Default Package',
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(
                          text: _defaultPackage,
                        ),
                        onChanged: (v) => _defaultPackage = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Content
              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              else if (_parsedRows == null)
                Expanded(
                  child:
                      _showPasteMode
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Paste CSV or TSV data:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Copy data from Excel, Google Sheets, or a text file and paste here.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
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
                                    onPressed:
                                        () => setState(
                                          () => _showPasteMode = false,
                                        ),
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
                                const Icon(
                                  Icons.upload_file,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Import inventory from CSV, TSV, or DigiKey export',
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: _pickAndParseCSV,
                                  icon: const Icon(Icons.file_open),
                                  label: const Text('Choose CSV File'),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed:
                                      () =>
                                          setState(() => _showPasteMode = true),
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
                        child: UnifiedDataGrid.local(
                          rows: _parsedRows!,
                          onRowsChanged:
                              (updated) =>
                                  setState(() => _parsedRows = updated),
                          columns: [
                            ColumnSpec(field: 'part_#', label: 'Part #'),
                            ColumnSpec(field: 'type', label: 'Type'),
                            ColumnSpec(field: 'value', label: 'Value'),
                            ColumnSpec(field: 'package', label: 'Package'),
                            ColumnSpec(
                              field: 'description',
                              label: 'Description',
                            ),
                            ColumnSpec(
                              field: 'qty',
                              label: 'Qty',
                              kind: CellKind.integer,
                            ),
                            ColumnSpec(field: 'location', label: 'Location'),
                            ColumnSpec(field: 'notes', label: 'Notes'),
                          ],
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
                    onPressed:
                        _isImporting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (_parsedRows != null)
                    FilledButton.icon(
                      onPressed: _isImporting ? null : _importToFirestore,
                      icon:
                          _isImporting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.check),
                      label: Text(
                        _isImporting
                            ? 'Importing...'
                            : 'Import ${_parsedRows!.length} Items',
                      ),
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

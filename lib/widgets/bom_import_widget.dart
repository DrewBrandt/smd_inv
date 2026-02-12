// lib/widgets/bom_import_widget.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/firestore_constants.dart';
import '../services/csv_parser_service.dart';
import '../services/inventory_matcher.dart';
import '../services/kicad_bom_parser.dart';

/// BOM import widget that replaces the grid during import
/// Provides visual feedback and matching preview before final import
class BomImportWidget extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<List<Map<String, dynamic>>> onImport;
  final FirebaseFirestore? firestore;

  const BomImportWidget({
    super.key,
    required this.onCancel,
    required this.onImport,
    this.firestore,
  });

  @override
  State<BomImportWidget> createState() => _BomImportWidgetState();
}

class _BomImportWidgetState extends State<BomImportWidget> {
  List<Map<String, dynamic>>? _parsedBom;
  int _skippedRows = 0;
  bool _isLoading = false;
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
      final parseResult = await CsvParserService.parseFromFile(
        expectedColumns: KicadBomParser.expectedColumns,
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

      await _parseBOMFromResult(parseResult);
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

      final parseResult = CsvParserService.parse(
        text,
        expectedColumns: KicadBomParser.expectedColumns,
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

      await _parseBOMFromResult(parseResult);
      setState(() => _showPasteMode = false);
    } catch (e) {
      setState(() {
        _error = 'Error parsing data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _parseBOMFromResult(CsvParseResult parseResult) async {
    final parsedResult = KicadBomParser.parse(parseResult);
    if (!parsedResult.success) {
      setState(() {
        _error = parsedResult.error ?? 'Failed to parse KiCad BOM.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _parsedBom = parsedResult.lines;
      _skippedRows = parsedResult.skippedRows;
      _isLoading = false;
    });

    // Auto-match with inventory
    await _matchInventory();
  }

  Future<void> _matchInventory() async {
    if (_parsedBom == null) return;

    try {
      final db = widget.firestore ?? FirebaseFirestore.instance;
      final inventory =
          await db.collection(FirestoreCollections.inventory).get();

      for (final line in _parsedBom!) {
        final attrs = line['required_attributes'] as Map<String, dynamic>;

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: attrs,
          inventorySnapshot: inventory,
        );

        if (matches.isEmpty) {
          line['_match_status'] = 'missing';
        } else if (matches.length == 1) {
          line['_match_status'] = 'matched';
          final matchData = matches.first.data();
          attrs[FirestoreFields.selectedComponentRef] = matches.first.id;
          line['_matched_part'] = {
            'id': matches.first.id,
            'part_#': matchData[FirestoreFields.partNumber],
            'qty': matchData[FirestoreFields.qty],
            'type': matchData['type'],
            'value': matchData['value'],
            'package': matchData['package'],
          };
        } else {
          line['_match_status'] = 'ambiguous';
          line['_multiple_matches'] =
              matches.map((m) {
                final data = m.data();
                return {
                  'id': m.id,
                  'part_#': data[FirestoreFields.partNumber],
                  'qty': data[FirestoreFields.qty],
                  'type': data['type'],
                  'value': data['value'],
                  'package': data['package'],
                  'location': data['location'],
                };
              }).toList();
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Error matching inventory: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_parsedBom != null) {
      return _buildReviewMode();
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _showPasteMode ? _buildPasteMode() : _buildUploadMode(),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewMode() {
    final cs = Theme.of(context).colorScheme;
    final total = _parsedBom!.length;
    final matched =
        _parsedBom!.where((l) => l['_match_status'] == 'matched').length;
    final ambiguous =
        _parsedBom!.where((l) => l['_match_status'] == 'ambiguous').length;
    final missing =
        _parsedBom!.where((l) => l['_match_status'] == 'missing').length;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review Imported BOM',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Parsed $total lines: $matched matched, $ambiguous ambiguous, $missing missing'
                  '${_skippedRows > 0 ? ' ($_skippedRows skipped)' : ''}',
                ),
                const SizedBox(height: 12),
                if (ambiguous > 0 || missing > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.35),
                      border: Border.all(
                        color: cs.error.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'You can import now and resolve unmatched lines in the board editor using Re-pair All or manual component selection.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 280,
                  child: ListView.builder(
                    itemCount: _parsedBom!.length,
                    itemBuilder: (context, i) {
                      final line = _parsedBom![i];
                      final attrs =
                          line['required_attributes'] as Map<String, dynamic>;
                      final status =
                          line['_match_status']?.toString() ?? 'pending';
                      final color = switch (status) {
                        'matched' => cs.tertiary,
                        'ambiguous' => cs.secondary,
                        'missing' => cs.error,
                        _ => cs.outline,
                      };
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.circle, size: 10, color: color),
                        title: Text('${line['designators']} (${line['qty']}x)'),
                        subtitle: Text(
                          [attrs['part_type'], attrs['value'], attrs['size']]
                              .where(
                                (v) =>
                                    (v?.toString().trim().isNotEmpty ?? false),
                              )
                              .join(' • '),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          () => setState(() {
                            _parsedBom = null;
                            _skippedRows = 0;
                          }),
                      child: const Text('Choose Different File'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => widget.onImport(_parsedBom!),
                      icon: const Icon(Icons.check),
                      label: const Text('Import Lines'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadMode() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.upload_file,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Import Bill of Materials',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Upload a CSV file from KiCad or paste BOM data',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!, style: TextStyle(color: cs.error)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_isLoading)
          const CircularProgressIndicator()
        else ...[
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
          const SizedBox(height: 12),
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        ],
      ],
    );
  }

  Widget _buildPasteMode() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _showPasteMode = false),
            ),
            const SizedBox(width: 8),
            Text(
              'Paste BOM Data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Paste CSV or TSV data with at least Reference/Designator and Quantity columns',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
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
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _showPasteMode = false),
              child: const Text('Back'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isLoading ? null : _parsePastedData,
              icon:
                  _isLoading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.check),
              label: const Text('Parse & Match'),
            ),
          ],
        ),
      ],
    );
  }
}

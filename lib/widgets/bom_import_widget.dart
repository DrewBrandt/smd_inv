// lib/widgets/bom_import_widget.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/firestore_constants.dart';
import '../services/csv_parser_service.dart';
import '../services/inventory_matcher.dart';

/// BOM import widget that replaces the grid during import
/// Provides visual feedback and matching preview before final import
class BomImportWidget extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<List<Map<String, dynamic>>> onImport;

  const BomImportWidget({
    super.key,
    required this.onCancel,
    required this.onImport,
  });

  @override
  State<BomImportWidget> createState() => _BomImportWidgetState();
}

class _BomImportWidgetState extends State<BomImportWidget> {
  List<Map<String, dynamic>>? _parsedBom;
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
        expectedColumns: ['Reference', 'Designator', 'Quantity', 'Qty', 'Value', 'Designation', 'Footprint'],
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
        expectedColumns: ['Reference', 'Designator', 'Quantity', 'Qty', 'Value', 'Designation', 'Footprint'],
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

  String _normalizeValue(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();

    // Unify µ → u, remove spaces
    s = s.replaceAll('µ', 'u').replaceAll(RegExp(r'\s+'), '');

    // Handle nF → n notation (use replaceAllMapped to avoid $ issues)
    s = s.replaceAllMapped(RegExp(r'(\d+\.?\d*)nF', caseSensitive: false), (m) => '${m.group(1)}n');
    s = s.replaceAllMapped(RegExp(r'(\d+\.?\d*)uF', caseSensitive: false), (m) => '${m.group(1)}u');
    s = s.replaceAllMapped(RegExp(r'(\d+\.?\d*)pF', caseSensitive: false), (m) => '${m.group(1)}p');

    // Drop trailing unit markers like 'uf', 'nf', 'pf' → keep just u/n/p
    s = s.replaceAll(RegExp(r'([unpkmM])f$', caseSensitive: false), r'$1');

    // "Embedded unit as decimal separator" forms:
    //  e.g., 2u2 → 2.2u, 100n0 → 100n
    // BUT keep resistance k notation as-is (e.g., 5k1, 78k7)
    final m = RegExp(r'^(\d+)([unpkmMG])(\d+)$').firstMatch(s);
    if (m != null) {
      final intPart = m.group(1)!;
      final unit = m.group(2)!.toLowerCase();
      final frac = m.group(3)!;

      // For resistors with 'k' notation, keep as-is (e.g., 5k1 stays 5k1)
      if (unit == 'k') {
        return s; // Keep original format for resistors
      }

      // For capacitors/inductors, convert to decimal (e.g., 2u2 → 2.2u)
      if (RegExp(r'^0+$').hasMatch(frac)) {
        return '$intPart$unit'; // e.g., 100n0 → 100n
      } else {
        return '$intPart.$frac$unit'; // e.g., 2u2 → 2.2u
      }
    }

    return s;
  }

  /// Detect component type from reference designator
  /// Categories: passives (R/L/C/D/LED) → 'components', connectors → 'connectors', everything else → 'ics'
  String _detectPartType(String ref) {
    // Passives (including diodes and LEDs)
    // Check LED before L to avoid matching LED as inductor
    if (ref.startsWith('LED')) return 'led';
    if (ref.startsWith('C')) return 'capacitor';
    if (ref.startsWith('R')) return 'resistor';
    if (ref.startsWith('L')) return 'inductor';
    if (ref.startsWith('D')) return 'diode';

    // Connectors
    if (ref.startsWith('J') || ref.startsWith('P') || ref.startsWith('X') || ref.startsWith('CON')) return 'connector';

    // Everything else is an IC (U, Q, BZ, etc.)
    return 'ic';
  }

  /// Detect category from part type
  String _detectCategory(String partType) {
    // Passives include R/L/C/D/LED
    const passives = ['capacitor', 'resistor', 'inductor', 'diode', 'led'];
    const connectors = ['connector'];

    if (passives.contains(partType)) return 'components';
    if (connectors.contains(partType)) return 'connectors';

    // Only ICs go under 'ics'
    return 'ics';
  }

  Future<void> _parseBOMFromResult(CsvParseResult parseResult) async {
    final parsed = <Map<String, dynamic>>[];

    // Detect column names (support multiple BOM formats, case-insensitive)
    String? refCol;
    String? qtyCol;
    String? valCol;
    String? fpCol;

    // Try to find columns case-insensitively
    for (final col in parseResult.columnMap.keys) {
      final lower = col.toLowerCase();
      if (lower.contains('reference') || lower.contains('designator')) refCol ??= col;
      if (lower.contains('quantity') || lower == 'qty') qtyCol ??= col;
      if (lower.contains('value') || lower.contains('designation')) valCol ??= col;
      if (lower.contains('footprint')) fpCol ??= col;
    }

    // Check for required columns
    if (refCol == null || qtyCol == null) {
      setState(() {
        _error = 'Could not find required columns (Reference/Designator and Quantity/Qty)';
        _isLoading = false;
      });
      return;
    }

    for (final row in parseResult.dataRows) {
      final designators = parseResult.getCellValue(row, refCol);
      final qty = int.tryParse(parseResult.getCellValue(row, qtyCol)) ?? 1;
      final valueRaw = valCol != null ? parseResult.getCellValue(row, valCol) : '';
      final value = _normalizeValue(valueRaw);
      final footprint = fpCol != null ? parseResult.getCellValue(row, fpCol) : '';

      if (designators.isEmpty) continue;

      // Skip DNP (Do Not Populate) and mounting holes
      if (valueRaw.toUpperCase() == 'DNP') continue;
      if (designators.toUpperCase().startsWith('H') && footprint.contains('MountingHole')) continue;

      // Detect component type from reference designator
      final ref = designators.split(',').first.trim();
      final partType = _detectPartType(ref);
      final category = _detectCategory(partType);

      // Extract package info from footprint
      String packageInfo = '';

      if (['capacitor', 'resistor', 'inductor', 'diode', 'led'].contains(partType)) {
        // For passives: extract size (0603, 0805, etc.)
        final sizeMatch = RegExp(r'(0201|0402|0603|0805|1206|1210|2512|1005|1608|2012|2520|3216|3225)').firstMatch(footprint);
        if (sizeMatch != null) {
          final extracted = sizeMatch.group(0)!;
          // Convert metric to imperial if needed (e.g., 1608 → 0603)
          final imperialSizes = {
            '1005': '0402',
            '1608': '0603',
            '2012': '0805',
            '3216': '1206',
            '2520': '1008',
            '3225': '1210',
          };
          packageInfo = imperialSizes[extracted] ?? extracted;
        }
      } else {
        // For ICs/connectors: extract package type (BGA, QFN, DFN, etc.)
        // Common IC package patterns
        final packagePatterns = [
          RegExp(r'\b(BGA|TFBGA|FBGA)\b', caseSensitive: false),
          RegExp(r'\b(QFN|VQFN|HVQFN|DHVQFN|PQFN)\b', caseSensitive: false),
          RegExp(r'\b(DFN)\b', caseSensitive: false),
          RegExp(r'\b(LQFP|QFP|TQFP)\b', caseSensitive: false),
          RegExp(r'\b(SOIC|SO|SOP)\b', caseSensitive: false),
          RegExp(r'\b(SOT-\d+)\b', caseSensitive: false),
          RegExp(r'\b(TSOP|TSSOP|SSOP)\b', caseSensitive: false),
          RegExp(r'\b(LGA)\b', caseSensitive: false),
          RegExp(r'\b(WLCSP|WLP)\b', caseSensitive: false),
          RegExp(r'\b(PSON)\b', caseSensitive: false),
        ];

        for (final pattern in packagePatterns) {
          final match = pattern.firstMatch(footprint);
          if (match != null) {
            packageInfo = match.group(0)!.toUpperCase();
            break;
          }
        }
      }

      parsed.add({
        'designators': designators,
        'qty': qty,
        'notes': '',
        'description': footprint.split(':').last.split('_').join(' '), // Use footprint as description
        'category': category,
        'required_attributes': {
          'part_type': partType,
          'value': value,
          'size': packageInfo,
          'selected_component_ref': null,
        },
        '_original_value': valueRaw,
        '_original_footprint': footprint,
        '_match_status': 'pending',
      });
    }

    setState(() {
      _parsedBom = parsed;
      _isLoading = false;
    });

    // Auto-match with inventory
    await _matchInventory();

    // Auto-import immediately after matching
    widget.onImport(_parsedBom!);
  }

  Future<void> _matchInventory() async {
    if (_parsedBom == null) return;

    try {
      final inventory = await FirebaseFirestore.instance
          .collection(FirestoreCollections.inventory)
          .get();

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
          line['_multiple_matches'] = matches.map((m) {
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
    // Show upload UI (matching happens automatically and imports immediately)
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

  Widget _buildUploadMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.upload_file, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'Import Bill of Materials',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Upload a CSV file from KiCad or paste BOM data',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
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
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ],
    );
  }

  Widget _buildPasteMode() {
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
            Text('Paste BOM Data', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Paste CSV or TSV data with at least Reference/Designator and Quantity columns',
          style: TextStyle(fontSize: 12, color: Colors.grey),
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
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Parse & Match'),
            ),
          ],
        ),
      ],
    );
  }
}

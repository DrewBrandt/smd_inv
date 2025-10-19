import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// import 'package:smd_inv/widgets/boards_editor/bom.dart'; // 1. REMOVE THIS IMPORT
import 'package:smd_inv/widgets/boards_editor/frontmatter.dart';
import '../models/board.dart';

// 2. ADD THESE IMPORTS
import 'package:smd_inv/widgets/collection_datagrid.dart';
import '../models/columns.dart';

class BoardEditorPage extends StatefulWidget {
  final String? boardId; // null => new
  const BoardEditorPage({super.key, this.boardId});

  @override
  State<BoardEditorPage> createState() => _BoardEditorPageState();
}

class _BoardEditorPageState extends State<BoardEditorPage> {
  bool _saving = false;
  bool _dirty = false;

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _image = TextEditingController();
  final _category = ValueNotifier<String?>('');

  Uint8List? _newImage;

  // 3. CHANGE STATE VARIABLE TYPE
  // final List<BomLine> _bom = []; // OLD
  final List<Map<String, dynamic>> _bom = []; // NEW

  @override
  void initState() {
    super.initState();
    if (widget.boardId != null) _load();
    _name.addListener(_markDirty);
    _desc.addListener(_markDirty);
    _category.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    final snap = await FirebaseFirestore.instance.collection('boards').doc(widget.boardId).get();
    if (!snap.exists) return;
    final b = BoardDoc.fromSnap(snap);
    setState(() {
      _name.text = b.name;
      _desc.text = b.description ?? '';
      _category.value = b.category;
      _image.text = b.imageUrl ?? '';

      // 4. CONVERT TO MAPS ON LOAD
      _bom
        ..clear()
        // ..addAll(b.bom); // OLD (b.bom is List<BomLine>)
        ..addAll(b.bom.map((line) => line.toMap())); // NEW
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);

    final ref =
        widget.boardId != null
            ? FirebaseFirestore.instance.collection('boards').doc(widget.boardId)
            : FirebaseFirestore.instance.collection('boards').doc();

    final now = FieldValue.serverTimestamp();
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category': (_category.value ?? '').isEmpty ? null : _category.value,
      'imageUrl': _image.text.trim().isEmpty ? null : _image.text.trim(),

      // 5. USE _bom DIRECTLY (it's already List<Map>)
      // 'bom': _bom.map((l) => l.toMap()).toList(), // OLD
      'bom': _bom, // NEW

      'updatedAt': now,
      if (widget.boardId == null) 'createdAt': now,
    };

    await ref.set(data, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    context.go('/boards');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.boardId == null ? 'Board created' : 'Board updated')));
  }

  Future<void> _cancel() async {
    if (!_dirty) return context.go('/boards');
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved changes. This will discard them.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
            ],
          ),
    );
    if (ok == true && mounted) context.go('/boards');
  }

  List<ColumnSpec> get _bomPassiveCols => [
    ColumnSpec(field: 'designators', label: 'Designators'), // Assuming 'designators' is top-level
    ColumnSpec(field: 'qty', kind: CellKind.integer),
    // Use dot-notation for nested fields
    ColumnSpec(field: 'required_attributes.part_type', capitalize: true),
    ColumnSpec(field: 'required_attributes.size'),
    ColumnSpec(field: 'required_attributes.value'),
    ColumnSpec(field: 'notes'),
  ];

  List<ColumnSpec> get _bomIcCols => [
    ColumnSpec(field: 'designators', label: 'Designators'),
    ColumnSpec(field: 'qty', kind: CellKind.integer),
    // Use dot-notation for nested fields
    ColumnSpec(field: 'required_attributes.part_#'),
    ColumnSpec(field: 'notes'),
  ];

  List<ColumnSpec> get _bomConnectorCols => [
    ColumnSpec(field: 'designators', label: 'Designators'),
    ColumnSpec(field: 'qty', kind: CellKind.integer),
    // Use dot-notation for nested fields
    ColumnSpec(field: 'required_attributes.part_#'),
    ColumnSpec(field: 'notes'),
  ];

  // 7. MODIFY Helper to add a new NESTED BOM line
  void _addBomLine({required String category, required Map<String, dynamic> reqAttrs}) {
    setState(() {
      _bom.add({
        'designators': '?',
        'qty': 1,
        'notes': '',
        'description': '', // Add any other top-level defaults
        'category': category,
        'required_attributes': {
          // Base attributes
          'part_type': '',
          'size': '',
          'value': '',
          'part_#': '',
          'selected_component_ref': null,
          ...reqAttrs, // Apply specific defaults
        },
      });
      _markDirty();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 8. UPDATE FILTERING LOGIC TO WORK ON MAPS
    // (This translates your old logic. Adjust if your BomLine.toMap() flattening is different)
    final passives =
        _bom
            .where(
              (l) =>
                  (l['category'] == 'components') &&
                  !((l['required_attributes']?['part_type'] ?? '').toString().toLowerCase().contains('conn')),
            )
            .toList();
    final ics =
        _bom
            .where(
              (l) =>
                  (l['category'] == 'ics') ||
                  ((l['required_attributes']?['part_#'] ?? '').toString().isNotEmpty &&
                      (l['required_attributes']?['part_type'] ?? '').toString().isEmpty),
            )
            .toList();
    final conns =
        _bom
            .where(
              (l) =>
                  (l['category'] == 'connectors') ||
                  ((l['required_attributes']?['part_type'] ?? '').toString().toLowerCase().contains('conn')),
            )
            .toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 4,
        color: cs.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FrontmatterSection(
                        name: _name,
                        desc: _desc,
                        category: _category,
                        image: _image,
                        onPickImage:
                            (bytes) => setState(() {
                              _newImage = bytes;
                              _markDirty();
                            }),
                        onClearImage:
                            () => setState(() {
                              _newImage = null;
                              _image.text = '';
                              _markDirty();
                            }),
                        onClone: () => debugPrint('Clone board...'),
                        onDelete: () => debugPrint('Delete board...'),
                      ),
                      const Divider(height: 64),
                      // 9. REPLACE BomTable WIDGETS
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Passives Section ---
                          Text('Passives', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          CollectionDataGrid(
                            rows: passives, 
                            columns: _bomPassiveCols,
                            persistKey: 'bom_passives_${widget.boardId ?? 'new'}', 
                            onRowsChanged: (updatedList) => _markDirty(), 
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Add Passive'),
                              // 9. MODIFY onPressed to call new _addBomLine
                              onPressed: () => _addBomLine(
                                category: 'components',
                                reqAttrs: {'part_type': 'RES'},
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- ICs Section ---
                          Text('ICs', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          CollectionDataGrid(
                            rows: ics,
                            columns: _bomIcCols,
                            persistKey: 'bom_ics_${widget.boardId ?? 'new'}',
                            onRowsChanged: (updatedList) => _markDirty(),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Add IC'),
                              // 9. MODIFY onPressed to call new _addBomLine
                              onPressed: () => _addBomLine(
                                category: 'ics',
                                reqAttrs: {'part_#': '?'},
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- Connectors Section ---
                          Text('Connectors', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          CollectionDataGrid(
                            rows: conns,
                            columns: _bomConnectorCols,
                            persistKey: 'bom_conns_${widget.boardId ?? 'new'}',
                            onRowsChanged: (updatedList) => _markDirty(),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Add Connector'),
                              // 9. MODIFY onPressed to call new _addBomLine
                              onPressed: () => _addBomLine(
                                category: 'connectors',
                                reqAttrs: {'part_#': '?', 'part_type': 'CONN'},
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ... (your existing save/cancel bar)
            Container(
              padding: const EdgeInsets.all(16),
              color: cs.surfaceContainerHighest,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _cancel, child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _saving || !_dirty ? null : _save,
                    icon:
                        _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 3))
                            : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

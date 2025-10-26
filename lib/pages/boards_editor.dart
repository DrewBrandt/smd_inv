// lib/pages/boards_editor.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/widgets/boards_editor/frontmatter.dart';
import 'package:smd_inv/widgets/bom_import_dialog.dart';
import '../models/board.dart';
import 'package:smd_inv/widgets/collection_datagrid.dart';
import '../models/columns.dart';

class BoardEditorPage extends StatefulWidget {
  final String? boardId;
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
  List<Map<String, dynamic>> _bom = [];

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
      _bom = b.bom.map((line) => line.toMap()).toList();
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

    // Handle image upload if new image selected
    String? imageUrl = _image.text.trim().isEmpty ? null : _image.text.trim();
    // TODO: If _newImage != null, upload to Firebase Storage and get URL

    final now = FieldValue.serverTimestamp();
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category': (_category.value ?? '').isEmpty ? null : _category.value,
      'imageUrl': imageUrl,
      'bom': _bom,
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

  Future<void> _importBOM() async {
    final imported = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => const BomImportDialog(),
    );

    if (imported != null && imported.isNotEmpty) {
      setState(() {
        _bom.addAll(imported);
        _markDirty();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Imported ${imported.length} BOM lines')));
    }
  }

  void _addBomLine() {
    setState(() {
      _bom.add({
        'designators': '?',
        'qty': 1,
        'notes': '',
        'description': '',
        'category': 'components',
        'required_attributes': {'part_type': '', 'size': '', 'value': '', 'part_#': '', 'selected_component_ref': null},
      });
      _markDirty();
    });
  }

  void _deleteLine(int index) {
    setState(() {
      _bom.removeAt(index);
      _markDirty();
    });
  }

  List<ColumnSpec> get _bomColumns => [
    ColumnSpec(field: 'designators', label: 'Designators'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ColumnSpec(field: 'required_attributes.part_type', label: 'Type', capitalize: true),
    ColumnSpec(field: 'required_attributes.value', label: 'Value'),
    ColumnSpec(field: 'required_attributes.size', label: 'Package'),
    ColumnSpec(field: 'required_attributes.part_#', label: 'Part #'),
    ColumnSpec(field: 'description', label: 'Description'),
    ColumnSpec(field: 'notes', label: 'Notes'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                    const Divider(height: 48),

                    // BOM Section Header
                    Row(
                      children: [
                        Text('Bill of Materials', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(width: 8),
                        Text('(${_bom.length} lines)', style: Theme.of(context).textTheme.bodyMedium),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _importBOM,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Import KiCad BOM'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _addBomLine,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Line'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Unified BOM Grid
                    if (_bom.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text('No BOM lines yet', style: TextStyle(color: Colors.grey.shade600)),
                              const SizedBox(height: 8),
                              const Text('Import from KiCad or add manually', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 500, // Fixed height for grid
                        child: CollectionDataGrid(
                          rows: _bom,
                          columns: _bomColumns,
                          persistKey: 'bom_editor_${widget.boardId ?? 'new'}',
                          onRowsChanged: (updated) {
                            setState(() => _bom = updated);
                            _markDirty();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Save/Cancel Bar
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

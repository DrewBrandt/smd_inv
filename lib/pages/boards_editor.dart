// lib/pages/board_editor_page.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/board.dart'; // your BoardDoc/BomLine models

class BoardEditorPage extends StatefulWidget {
  final String? boardId; // null => new
  const BoardEditorPage({super.key, this.boardId});

  @override
  State<BoardEditorPage> createState() => _BoardEditorPageState();
}

class _BoardEditorPageState extends State<BoardEditorPage> {
  // Stepper state
  int _step = 0;
  bool _saving = false;

  // Form fields
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _category = ValueNotifier<String?>(''); // FC / Radio / GS / Misc
  final _colorHex = TextEditingController(); // "#2D7FF9"
  String? _imageUrl; // existing
  Uint8List? _newImage; // staged new image bytes

  // BOM state (editable list)
  final List<BomLine> _bom = [];

  // Load existing (edit mode)
  @override
  void initState() {
    super.initState();
    if (widget.boardId != null) {
      _load();
    }
  }

  Future<void> _load() async {
    final snap = await FirebaseFirestore.instance.collection('boards').doc(widget.boardId).get();
    if (!snap.exists) return;
    final b = BoardDoc.fromSnap(snap);
    setState(() {
      _name.text = b.name;
      _desc.text = b.description ?? '';
      _category.value = b.category;
      _colorHex.text = b.color ?? '';
      _imageUrl = b.imageUrl;
      _bom
        ..clear()
        ..addAll(b.bom);
    });
  }

  // Save/create
  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      setState(() => _step = 0);
      return;
    }
    setState(() => _saving = true);

    final col = FirebaseFirestore.instance.collection('boards');
    final ref = widget.boardId != null ? col.doc(widget.boardId) : col.doc();
    String? imageUrl = _imageUrl;

    // // Upload staged image if present
    // if (_newImage != null) {
    //   final path = 'boards/${ref.id}/cover.jpg';
    //   final task = await FirebaseStorage.instance
    //       .ref(path)
    //       .putData(_newImage!, SettableMetadata(contentType: 'image/jpeg'));
    //   imageUrl = await task.ref.getDownloadURL();
    // }

    final now = FieldValue.serverTimestamp();
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category': (_category.value ?? '').isEmpty ? null : _category.value,
      'color': _colorHex.text.trim().isEmpty ? null : _colorHex.text.trim(),
      'imageUrl': imageUrl,
      'bom': _bom.map((l) => l.toMap()).toList(),
      'updatedAt': now,
      if (widget.boardId == null) 'createdAt': now,
    };

    await ref.set(data, SetOptions(merge: true));

    if (mounted) {
      setState(() => _saving = false);
      // go to detail page if you have it, or back to boards list
      context.go('/boards');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.boardId == null ? 'Board created' : 'Board updated')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              widget.boardId == null ? 'New Board' : 'Edit Board',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => context.go('/boards'),
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Wizard
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                // Left rail (steps)
                Container(
                  width: 220,
                  color: cs.surface.withAlpha(127),
                  child: ListView(
                    children: [
                      _StepTile(index: 0, current: _step, title: 'Basics', onTap: () => setState(() => _step = 0)),
                      _StepTile(index: 1, current: _step, title: 'BOM', onTap: () => setState(() => _step = 1)),
                      _StepTile(index: 2, current: _step, title: 'Review', onTap: () => setState(() => _step = 2)),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IndexedStack(
                      index: _step,
                      children: [
                        _BasicsStep(
                          name: _name,
                          desc: _desc,
                          category: _category,
                          colorHex: _colorHex,
                          imageUrl: _imageUrl,
                          onPickImage: (bytes) => setState(() => _newImage = bytes),
                          onClearImage:
                              () => setState(() {
                                _newImage = null;
                                _imageUrl = null;
                              }),
                        ),
                        _BomStep(bom: _bom, onChanged: () => setState(() {})),
                        _ReviewStep(
                          bom: _bom,
                          name: _name.text,
                          category: _category.value,
                          imageUrl: _imageUrl,
                          colorHex: _colorHex.text,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Steps
// ─────────────────────────────────────────────────────────────

class _BasicsStep extends StatelessWidget {
  final TextEditingController name, desc, colorHex;
  final ValueNotifier<String?> category;
  final String? imageUrl;
  final ValueChanged<Uint8List> onPickImage;
  final VoidCallback onClearImage;

  const _BasicsStep({
    required this.name,
    required this.desc,
    required this.category,
    required this.colorHex,
    required this.imageUrl,
    required this.onPickImage,
    required this.onClearImage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Future<void> pickImage() async {
      // desktop/web-friendly quick picker
      // you can swap for file_picker if you prefer
      final input = await showDialog<Uint8List?>(context: context, builder: (c) => _ImagePickerDialog());
      if (input != null) onPickImage(input);
    }

    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('Name'),
          TextField(controller: name, decoration: const InputDecoration(hintText: 'Board name')),

          const SizedBox(height: 16),
          label('Description'),
          TextField(
            controller: desc,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label('Category'),
                    ValueListenableBuilder<String?>(
                      valueListenable: category,
                      builder:
                          (_, v, _) => DropdownButtonFormField<String>(
                            initialValue: (v?.isEmpty ?? true) ? null : v,
                            items: const [
                              DropdownMenuItem(value: 'fc', child: Text('FC')),
                              DropdownMenuItem(value: 'radio', child: Text('Radio')),
                              DropdownMenuItem(value: 'gs', child: Text('GS')),
                              DropdownMenuItem(value: 'misc', child: Text('Misc')),
                            ],
                            onChanged: (x) => category.value = x,
                            hint: const Text('Select a category'),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label('Color (hex)'),
                    TextField(
                      controller: colorHex,
                      decoration: const InputDecoration(prefixText: '# (or full hex with #)'),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          label('Cover image'),
          Row(
            children: [
              Container(
                width: 96,
                height: 96,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: cs.surface),
                child:
                    imageUrl != null
                        ? Image.network(imageUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.image_outlined, size: 40),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(onPressed: pickImage, icon: const Icon(Icons.upload), label: const Text('Upload')),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onClearImage,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BomStep extends StatelessWidget {
  final List<BomLine> bom;
  final VoidCallback onChanged;
  const _BomStep({required this.bom, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    void addLine() {
      bom.add(BomLine(qty: 1, category: 'components', requiredAttributes: {}, selectedComponentRef: null, notes: null));
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('BOM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            OutlinedButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Add line')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                // _importBomCsv(context, bom).then((_) => onChanged());
              },
              icon: const Icon(Icons.file_upload),
              label: const Text('Import KiCad CSV'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // simple editable table
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              itemCount: bom.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
              itemBuilder: (context, i) {
                final line = bom[i];
                final attrs = Map<String, dynamic>.from(line.requiredAttributes);
                final qtyCtrl = TextEditingController(text: line.qty.toString());
                final catCtrl = TextEditingController(text: line.category ?? '');
                final sizeCtrl = TextEditingController(text: '${attrs['size'] ?? ''}');
                final valueCtrl = TextEditingController(text: '${attrs['value'] ?? ''}');
                final typeCtrl = TextEditingController(text: '${attrs['part_type'] ?? ''}');
                final pnCtrl = TextEditingController(text: '${attrs['part_#'] ?? ''}');

                void commit() {
                  final q = int.tryParse(qtyCtrl.text) ?? 0;
                  bom[i] = BomLine(
                    qty: q,
                    category: catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
                    requiredAttributes: {
                      if (typeCtrl.text.trim().isNotEmpty) 'part_type': typeCtrl.text.trim(),
                      if (sizeCtrl.text.trim().isNotEmpty) 'size': sizeCtrl.text.trim(),
                      if (valueCtrl.text.trim().isNotEmpty) 'value': valueCtrl.text.trim(),
                      if (pnCtrl.text.trim().isNotEmpty) 'part_#': pnCtrl.text.trim(),
                    },
                    selectedComponentRef: line.selectedComponentRef,
                    notes: line.notes,
                  );
                  onChanged();
                }

                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                          onChanged: (_) => commit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: catCtrl,
                          decoration: const InputDecoration(labelText: 'Category', isDense: true),
                          onChanged: (_) => commit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: typeCtrl,
                          decoration: const InputDecoration(labelText: 'Part type', isDense: true),
                          onChanged: (_) => commit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: sizeCtrl,
                          decoration: const InputDecoration(labelText: 'Size', isDense: true),
                          onChanged: (_) => commit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: valueCtrl,
                          decoration: const InputDecoration(labelText: 'Value', isDense: true),
                          onChanged: (_) => commit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: pnCtrl,
                          decoration: const InputDecoration(labelText: 'Part #', isDense: true),
                          onChanged: (_) => commit(),
                        ),
                      ),
                      const Spacer(),
                      // pin specific component
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ref = await _pickComponent(context, attrs);
                          bom[i] = BomLine(
                            qty: line.qty,
                            category: line.category,
                            requiredAttributes: attrs,
                            selectedComponentRef: ref,
                            notes: line.notes,
                          );
                          onChanged();
                        },
                        icon: const Icon(Icons.link),
                        label: Text(line.selectedComponentRef == null ? 'Choose component' : 'Change'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          bom.removeAt(i);
                          onChanged();
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final List<BomLine> bom;
  final String name;
  final String? category;
  final String? imageUrl;
  final String colorHex;

  const _ReviewStep({
    required this.bom,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.colorHex,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Summary', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            _pill('Name', name),
            if ((category ?? '').isNotEmpty) _pill('Category', category!),
            if (colorHex.isNotEmpty) _pill('Color', colorHex),
            _pill('BOM lines', '${bom.length}'),
          ],
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 16),
        const Text('Looks good? Click Save in the top-right.'),
      ],
    );
  }

  Widget _pill(String k, String v) {
    return Chip(label: Text('$k: $v'));
  }
}

// ─────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────

class _StepTile extends StatelessWidget {
  final int index, current;
  final String title;
  final VoidCallback onTap;
  const _StepTile({required this.index, required this.current, required this.title, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final active = index == current;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      selected: active,
      selectedTileColor: cs.primaryContainer.withAlpha(127),
      leading: CircleAvatar(
        radius: 12,
        backgroundColor: active ? cs.primary : cs.surface,
        child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: active ? cs.onPrimary : cs.onSurfaceVariant)),
      ),
      title: Text(title, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w600)),
      onTap: onTap,
    );
  }
}

// fake image picker dialog (replace with file_picker or image_picker_web for real usage)
class _ImagePickerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Image picker placeholder'),
      content: const Text('Wire this up to file_picker/image_picker for real uploads.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

Future<DocumentReference<Map<String, dynamic>>?> _pickComponent(
  BuildContext context,
  Map<String, dynamic> requiredAttrs,
) async {
  final db = FirebaseFirestore.instance;

  // Start broad; optionally add where clauses (e.g., category/size/value) if you store them as fields.
  final qs = await db.collection('components').limit(50).get();
  final items = qs.docs;

  return showDialog<DocumentReference<Map<String, dynamic>>?>(
    context: context,
    builder: (c) {
      return AlertDialog(
        title: const Text('Choose component'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = items[i];
              final m = d.data();
              final name = (m['name'] ?? m['part_#'] ?? d.id).toString();
              final size = (m['size'] ?? '').toString();
              final value = (m['value'] ?? '').toString();
              final loc = (m['location'] ?? '').toString();
              return ListTile(
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([value, size, loc].where((s) => s.isNotEmpty).join(' • ')),
                onTap: () => Navigator.pop(c, d.reference),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
      );
    },
  );
}

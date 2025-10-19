// lib/pages/board_editor_page.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/ui/category_colors.dart';
import '../models/board.dart';

class BoardEditorPage extends StatefulWidget {
  final String? boardId; // null => new
  const BoardEditorPage({super.key, this.boardId});

  @override
  State<BoardEditorPage> createState() => _BoardEditorPageState();
}

class _BoardEditorPageState extends State<BoardEditorPage> {
  // form state
  bool _saving = false;
  bool _dirty = false;

  // Frontmatter
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _image = TextEditingController();
  final _category = ValueNotifier<String?>('');
  // ignore: unused_field
  Uint8List? _newImage; // (upload stubbed; wire Storage later)

  // BOM
  final List<BomLine> _bom = [];

  @override
  void initState() {
    super.initState();
    if (widget.boardId != null) _load();
    // mark dirty on field changes
    _name.addListener(() => _markDirty());
    _desc.addListener(() => _markDirty());
    _category.addListener(() => _markDirty());
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
      _bom
        ..clear()
        ..addAll(b.bom);
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);

    final col = FirebaseFirestore.instance.collection('boards');
    final ref = widget.boardId != null ? col.doc(widget.boardId) : col.doc();

    // Optional image upload (stubbed for now)
    // if (_newImage != null) { ... upload to Storage ... imageUrl = downloadUrl; }

    final now = FieldValue.serverTimestamp();
    final data = {
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'category': (_category.value ?? '').isEmpty ? null : _category.value,
      'imageUrl': _image.text.trim().isEmpty ? null : _image.text.trim(),
      'bom': _bom.map((l) => l.toMap()).toList(),
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
    if (!_dirty) {
      context.go('/boards');
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Content
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // FRONTMATTER
                Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _FrontmatterSection(
                      onClone: () => {},
                      onDelete: () => {},
                      name: _name,
                      desc: _desc,
                      category: _category,
                      image: _image,
                      onPickImage: (bytes) {
                        setState(() {
                          _newImage = bytes;
                          _markDirty();
                        });
                      },
                      onClearImage: () {
                        setState(() {
                          _newImage = null;
                          _image.text = '';
                          _markDirty();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // BOM
                Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _BomSection(bom: _bom, onChanged: () => setState(_markDirty)),
                  ),
                ),

                const SizedBox(height: 88), // leave room for sticky footer
              ],
            ),
          ),
        ),

        // Sticky footer actions (inside the page)
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
                const Spacer(),
                if (_dirty) Text('Unsaved changes', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Sections
// ─────────────────────────────────────────────────────────────

class _FrontmatterSection extends StatefulWidget {
  final TextEditingController name, desc, image;
  final ValueNotifier<String?> category;
  final ValueChanged<Uint8List> onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onClone;
  final VoidCallback onDelete;

  const _FrontmatterSection({
    required this.name,
    required this.desc,
    required this.category,
    required this.image,
    required this.onPickImage,
    required this.onClearImage,
    required this.onClone,
    required this.onDelete,
  });

  @override
  State<_FrontmatterSection> createState() => _FrontmatterSectionState();
}

class _FrontmatterSectionState extends State<_FrontmatterSection> {
  bool _hovering = false;

  Future<void> _pickImage() async {
    final input = await showDialog<Uint8List?>(context: context, builder: (c) => const _ImagePickerDialog());
    if (input != null) widget.onPickImage(input);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Flexible(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT COLUMN — form fields
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top line (name + category + URL)
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: widget.name,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: ValueListenableBuilder<String?>(
                        valueListenable: widget.category,
                        builder:
                            (_, v, _) => DropdownButtonFormField<String>(
                              initialValue: (v?.isEmpty ?? true) ? null : v,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: kCategoryColors.keys
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: categoryColor(c, cs.onSurface),
                                              borderRadius: BorderRadius.circular(2),
                                              border: Border.all(color: cs.outline),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(c),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (x) => widget.category.value = x,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: widget.image,
                        decoration: const InputDecoration(
                          labelText: 'Image URL',
                          hintText: 'https://example.com/image.jpg',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: widget.desc,
                  minLines: 3,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // IMAGE PREVIEW
          MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    image:
                        (widget.image.text.isNotEmpty)
                            ? DecorationImage(image: NetworkImage(widget.image.text), fit: BoxFit.cover)
                            : null,
                    borderRadius: BorderRadius.circular(90),
                    border: Border.all(color: cs.outline, width: 2),
                    boxShadow: [BoxShadow(color: cs.shadow.withAlpha(100), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  child: (widget.image.text.isEmpty) ? const Center(child: Icon(Icons.image_outlined, size: 48)) : null,
                ),
                if (_hovering)
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(50),
                      borderRadius: BorderRadius.circular(90),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: 'Upload / Replace',
                          child: IconButton.filledTonal(
                            icon: Icon(Icons.upload, color: cs.onPrimaryContainer),
                            onPressed: _pickImage,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: 'Remove',
                          child: IconButton.filledTonal(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: Colors.redAccent.withAlpha(200)),
                            onPressed: widget.onClearImage,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // CLONE/DELETE COLUMN
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: 'Clone this board',
                  child: OutlinedButton(
                    onPressed: widget.onClone,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cs.outline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 10.0), child: Icon(Icons.copy_all_rounded, size: 40)),
                  ),
                ),
                SizedBox(height: 16),
                Tooltip(
                  message: 'Delete this board',
                  child: FilledButton(
                    onPressed: widget.onDelete,
            
                    style: FilledButton.styleFrom(
                      
                      side: BorderSide(color: cs.outline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 10.0), child: Icon(Icons.delete_forever_rounded, size: 40,)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerDialog extends StatelessWidget {
  const _ImagePickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Image picker placeholder'),
      content: const Text('Wire this up to file_picker/image_picker for real uploads.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _BomSection extends StatelessWidget {
  final List<BomLine> bom;
  final VoidCallback onChanged;
  const _BomSection({required this.bom, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    void addLine() {
      bom.add(
        BomLine(qty: 1, category: 'components', requiredAttributes: const {}, selectedComponentRef: null, notes: null),
      );
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bill of Materials', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Add line')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: import KiCad CSV then onChanged();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('CSV import not implemented yet')));
              },
              icon: const Icon(Icons.file_upload),
              label: const Text('Import KiCad CSV'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

Future<DocumentReference<Map<String, dynamic>>?> _pickComponent(
  BuildContext context,
  Map<String, dynamic> requiredAttrs,
) async {
  final db = FirebaseFirestore.instance;
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

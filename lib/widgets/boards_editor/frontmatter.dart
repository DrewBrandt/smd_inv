import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:smd_inv/ui/category_colors.dart';

class FrontmatterSection extends StatefulWidget {
  final TextEditingController name, desc, image;
  final ValueNotifier<String?> category;
  final ValueChanged<Uint8List> onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onClone;
  final VoidCallback onDelete;

  const FrontmatterSection({
    super.key,
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
  State<FrontmatterSection> createState() => _FrontmatterSectionState();
}

class _FrontmatterSectionState extends State<FrontmatterSection> {
  bool _hovering = false;

  Future<void> _pickImage() async {
    final input = await showDialog<Uint8List?>(context: context, builder: (c) => const _ImagePickerDialog());
    if (input != null) widget.onPickImage(input);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fields
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            (_, v, __) => DropdownButtonFormField<String>(
                              initialValue: (v?.isEmpty ?? true) ? null : v,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items:
                                  kCategoryColors.keys.map((c) {
                                    return DropdownMenuItem<String>(
                                      value: c,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: categoryColor(c, cs.onSurface),
                                              border: Border.all(color: cs.outline),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                          Text(c),
                                        ],
                                      ),
                                    );
                                  }).toList(),
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
          // Image
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
                        widget.image.text.isNotEmpty
                            ? DecorationImage(image: NetworkImage(widget.image.text), fit: BoxFit.cover)
                            : null,
                    borderRadius: BorderRadius.circular(90),
                    border: Border.all(color: cs.outline, width: 2),
                    boxShadow: [BoxShadow(color: cs.shadow.withAlpha(100), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  child: widget.image.text.isEmpty ? const Center(child: Icon(Icons.image_outlined, size: 48)) : null,
                ),
                if (_hovering)
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(90),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(icon: const Icon(Icons.upload), onPressed: _pickImage),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.delete_outline),
                          style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: widget.onClearImage,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Clone / Delete
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Icon(Icons.copy_all_rounded, size: 40),
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Tooltip(
                  message: 'Delete this board',
                  child: FilledButton(
                    onPressed: widget.onDelete,

                    style: FilledButton.styleFrom(
                      side: BorderSide(color: cs.outline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Icon(Icons.delete_forever_rounded, size: 40),
                    ),
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Image picker placeholder'),
    content: const Text('Wire this up later.'),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}

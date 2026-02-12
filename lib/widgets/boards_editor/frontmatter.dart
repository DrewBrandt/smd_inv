import 'package:flutter/material.dart';

/// Category color mapping
const Map<String, Color> kCategoryColors = {
  'Radio': Color(0xFF77C0FC),
  'FC': Color(0xFF88E08B),
  'GS': Color.fromARGB(255, 255, 165, 19),
  'Misc': Colors.grey,
};

Color categoryColor(String? key, Color fallback) {
  if (key == null) return fallback;
  return kCategoryColors[key] ?? fallback;
}

class FrontmatterSection extends StatefulWidget {
  final TextEditingController name;
  final TextEditingController desc;
  final TextEditingController image;
  final ValueNotifier<String?> category;
  final VoidCallback onClearImage;
  final VoidCallback onClone;
  final VoidCallback onDelete;
  final bool canEdit;

  const FrontmatterSection({
    super.key,
    required this.name,
    required this.desc,
    required this.category,
    required this.image,
    required this.onClearImage,
    required this.onClone,
    required this.onDelete,
    required this.canEdit,
  });

  @override
  State<FrontmatterSection> createState() => _FrontmatterSectionState();
}

class _FrontmatterSectionState extends State<FrontmatterSection> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFields(cs, compact: true),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [_buildImage(cs), _buildActions(cs, compact: true)],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildFields(cs, compact: false)),
            const SizedBox(width: 24),
            _buildImage(cs),
            const SizedBox(width: 24),
            _buildActions(cs, compact: false),
          ],
        );
      },
    );
  }

  Widget _buildFields(ColorScheme cs, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Column(
            children: [
              TextField(
                controller: widget.name,
                enabled: widget.canEdit,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _buildCategoryDropdown(cs),
              const SizedBox(height: 12),
              TextField(
                controller: widget.image,
                enabled: widget.canEdit,
                decoration: const InputDecoration(
                  labelText: 'Image URL',
                  hintText: 'https://example.com/image.jpg',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: widget.name,
                  enabled: widget.canEdit,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 1, child: _buildCategoryDropdown(cs)),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: widget.image,
                  enabled: widget.canEdit,
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
          enabled: widget.canEdit,
          minLines: 3,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(ColorScheme cs) {
    return ValueListenableBuilder<String?>(
      valueListenable: widget.category,
      builder: (context, v, child) {
        return DropdownButtonFormField<String>(
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
          onChanged: widget.canEdit ? (x) => widget.category.value = x : null,
        );
      },
    );
  }

  Widget _buildImage(ColorScheme cs) {
    return MouseRegion(
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
                      ? DecorationImage(
                        image: NetworkImage(widget.image.text),
                        fit: BoxFit.cover,
                      )
                      : null,
              borderRadius: BorderRadius.circular(90),
              border: Border.all(color: cs.outline, width: 2),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withAlpha(100),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child:
                widget.image.text.isEmpty
                    ? const Center(child: Icon(Icons.image_outlined, size: 48))
                    : null,
          ),
          if (_hovering)
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(90),
              ),
              child: Center(
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  onPressed: widget.canEdit ? widget.onClearImage : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme cs, {required bool compact}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: compact ? 100 : 180),
      child: Wrap(
        direction: compact ? Axis.horizontal : Axis.vertical,
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          Tooltip(
            message: 'Clone this board',
            child: OutlinedButton.icon(
              onPressed: widget.canEdit ? widget.onClone : null,
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text('Clone'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Delete this board',
            child: FilledButton.icon(
              onPressed: widget.canEdit ? widget.onDelete : null,
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Delete'),
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/readiness.dart';
import '../ui/category_colors.dart';
import 'make_sheet.dart';

class BoardListItem extends StatelessWidget {
  final BoardDoc board;
  final Readiness readiness;
  final VoidCallback onOpen;
  final Future<void> Function()? onDuplicate;
  final Future<void> Function(int qty)? onMake;

  const BoardListItem({
    super.key,
    required this.board,
    required this.readiness,
    required this.onOpen,
    this.onDuplicate,
    this.onMake,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = readiness.buildableQty > 0 && readiness.shortfalls.isEmpty;
    final partial = readiness.buildableQty > 0 && readiness.shortfalls.isNotEmpty;

    Icon statusIcon() {
      if (ready) return Icon(Icons.check_circle, color: Colors.green.shade700);
      if (partial) return Icon(Icons.error_outline, color: Colors.orange.shade700);
      return Icon(Icons.cancel_outlined, color: Colors.red.shade700);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: cs.surface,
                  image:
                      (board.imageUrl?.isNotEmpty ?? false)
                          ? DecorationImage(image: NetworkImage(board.imageUrl!), fit: BoxFit.cover)
                          : null,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: cs.onSurface, width: 0.5),
                  boxShadow: [BoxShadow(color: cs.shadow.withAlpha(100), blurRadius: 4, offset: const Offset(0, 2))],
                ),
              ),
              const SizedBox(width: 12),

              // Title + sub
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            board.name,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        statusIcon(),
                      ],
                    ),
                    if ((board.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          board.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if ((board.category ?? '').isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: categoryColor(board.category, cs.surfaceContainer),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              board.category!,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          'Parts: ${board.bom.length}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Readiness
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Can make: ', style: TextStyle(color: cs.onSurfaceVariant)),
                        Text(
                          '${readiness.buildableQty}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: readiness.readyPct),
                    ),
                    const SizedBox(height: 6),
                    if (readiness.shortfalls.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in readiness.shortfalls.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(20),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.red.withAlpha(75)),
                              ),
                              child: Text(
                                '${s.label} ×${s.missing}',
                                style: const TextStyle(fontSize: 12, color: Colors.red),
                              ),
                            ),
                          if (readiness.shortfalls.length > 3)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(20),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.red.withAlpha(75)),
                              ),
                              child: Text(
                                '+${readiness.shortfalls.length - 3} more',
                                style: const TextStyle(fontSize: 12, color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed:
                        onMake == null
                            ? null
                            : () async {
                              final qty = await showMakeSheet(context, maxQty: readiness.buildableQty);
                              if (qty != null) await onMake!(qty);
                            },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Make'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(tooltip: 'Open', onPressed: onOpen, icon: const Icon(Icons.chevron_right)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

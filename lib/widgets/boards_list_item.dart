import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/models/board.dart';

final Map<String, Color> _categoryColors = {
  'radio': const Color.fromARGB(255, 119, 192, 252),
  'fc': const Color.fromARGB(255, 136, 224, 139),
  'gs': Colors.orange,
  'test': Colors.purple,
};



class BoardListItem extends StatelessWidget {
  final BoardDoc board;
  final int buildableQty; // precomputed
  final double bomReadyPct; // 0..1
  final List<Shortfall> shortfallsTop; // e.g., up to 3 items
  final int shortfallsMore; // remaining count

  const BoardListItem({
    super.key,
    required this.board,
    required this.buildableQty,
    required this.bomReadyPct,
    required this.shortfallsTop,
    required this.shortfallsMore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = buildableQty > 0 && shortfallsTop.isEmpty;
    final partial = buildableQty > 0 && shortfallsTop.isNotEmpty;

    Icon statusIcon() {
      if (ready) return Icon(Icons.check_circle, color: Colors.green.shade700);
      if (partial) return Icon(Icons.error_outline, color: Colors.orange.shade700);
      return Icon(Icons.cancel_outlined, color: Colors.red.shade700);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/boards/${board.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(color: cs.shadow.withAlpha(100), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                  color: _parseColor(board.color, cs.surface),
                  image:
                      board.imageUrl != null
                          ? DecorationImage(image: NetworkImage(board.imageUrl!), fit: BoxFit.cover)
                          : null,
                  borderRadius: BorderRadius.all(Radius.circular(50.0)),
                  border: Border.all(color: cs.onSurface, width: 0.5),
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
                      spacing: 8,
                      children: [
                        if ((board.category ?? '').isNotEmpty) _chip(board.category!, cs),
                        _meta('Parts', '${board.bom.length}'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Readiness module
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Can make
                    Row(
                      children: [
                        Text('Can make: ', style: TextStyle(color: cs.onSurfaceVariant)),
                        Text('$buildableQty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Progress
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: bomReadyPct),
                    ),
                    const SizedBox(height: 6),
                    // Shortfalls (top 3) + +N more
                    if (shortfallsTop.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in shortfallsTop) _shortfallChip('${s.label} ×${s.missing}'),
                          if (shortfallsMore > 0) _shortfallChip('+$shortfallsMore more'),
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
                    onPressed: () => _showMakeSheet(context, board, buildableQty),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Make'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Open',
                    // onPressed: () => context.go('/boards/${board.id}'),
                    onPressed: () async {
                      final newId = await duplicateBoard(board.id);
                      debugPrint('Cloned to $newId');
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- helpers (keep trivial) ---
  Widget _chip(String text, ColorScheme cs) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: _categoryColors[text.toLowerCase()] ?? cs.surfaceContainer, borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
  );

  Widget _meta(String k, String v) => Align(alignment: Alignment.centerLeft, child: Text('$k: $v', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _shortfallChip(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.red.withOpacity(.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.red.withOpacity(.3)),
    ),
    child: Text(t, style: const TextStyle(fontSize: 12, color: Colors.red)),
  );

  void _showMakeSheet(BuildContext context, BoardDoc b, int maxQty) {
    int qty = (maxQty > 0) ? 1 : 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (c) => Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Quantity'),
                const SizedBox(width: 12),
                IconButton(
                  onPressed:
                      qty > 0
                          ? () {
                            qty = (qty - 1).clamp(0, maxQty);
                            (c as Element).markNeedsBuild();
                          }
                          : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                IconButton(
                  onPressed:
                      qty < maxQty
                          ? () {
                            qty = (qty + 1).clamp(0, maxQty);
                            (c as Element).markNeedsBuild();
                          }
                          : null,
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                FilledButton(
                  onPressed:
                      qty > 0
                          ? () {
                            Navigator.pop(c); /* call your build/consume flow */
                          }
                          : null,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ),
    );
  }

  String _initials(String s) => s.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();

  Color _parseColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final h = hex.replaceAll('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    return fallback;
  }
}

class Shortfall {
  final String label; // e.g., "10k 0402" or "ESP32"
  final int missing;
  Shortfall(this.label, this.missing);
}

class Readiness {
  final int buildableQty; // e.g., 0, 1, 2...
  final double readyPct; // 0.0..1.0
  final List<Shortfall> shortfalls;

  Readiness({required this.buildableQty, required this.readyPct, required this.shortfalls});
}

Future<String> duplicateBoard(String sourceId, {String? newName}) async {
  final db = FirebaseFirestore.instance;
  final srcRef = db.collection('boards').doc(sourceId);
  final snap = await srcRef.get();
  if (!snap.exists) {
    throw StateError('Board $sourceId not found');
  }

  // Shallow clone of the document data
  final data = Map<String, dynamic>.from(snap.data()!);

  // Optional tweaks so the copy is distinguishable + sorted correctly
  data['name'] = newName ?? '${data['name']} (copy)';
  data['createdAt'] = FieldValue.serverTimestamp();
  data['updatedAt'] = FieldValue.serverTimestamp();

  // Write to a new doc with an auto ID
  final dstRef = db.collection('boards').doc();
  await dstRef.set(data);

  return dstRef.id;
}

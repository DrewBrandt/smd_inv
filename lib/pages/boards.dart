// lib/pages/boards_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/data/firebase_datagrid_source.dart';
import 'package:smd_inv/data/firestore_streams.dart';
import 'package:smd_inv/widgets/boards_list_item.dart';
import '../models/board.dart';

// --- Add this import if BoardListItem is in another file.
// import 'board_list_item.dart';

class BoardsView extends StatelessWidget {
  const BoardsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StreamBuilder<List<Doc>>(
            stream: collectionStream('boards'),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final boards = snap.data!.map(BoardDoc.fromSnap).toList();
              if (boards.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No boards yet'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Add your first board'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: boards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final b = boards[i];
                  final r = computeReadinessStub(b); // TODO: wire to real inventory
                  return BoardListItem(
                    board: b,
                    buildableQty: r.buildableQty,
                    bomReadyPct: r.readyPct,
                    shortfallsTop: r.shortfalls.take(3).toList(),
                    shortfallsMore: (r.shortfalls.length > 3) ? r.shortfalls.length - 3 : 0,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

Readiness computeReadinessStub(BoardDoc b) {
  // Super naive: show 100% ready if there are any BOM lines; otherwise 0.
  // Replace with real math using your inventory.
  if (b.bom.isEmpty) {
    return Readiness(buildableQty: 0, readyPct: 0.0, shortfalls: const []);
  }

  // Pretend we can make 1 if there is at least one line and no explicit "notes: missing"
  final missing = <Shortfall>[];
  for (final line in b.bom) {
    final ra = line.requiredAttributes;
    final label = [
      if (ra['value'] != null) ra['value'],
      if (ra['size'] != null) ra['size'],
      if (ra['part_type'] != null) ra['part_type'],
      if (ra['part_#'] != null) ra['part_#'],
    ].whereType<String>().join(' ');
    // demo condition to show chips:
    if ((line.notes ?? '').toLowerCase().contains('missing')) {
      missing.add(Shortfall(label.isEmpty ? 'part' : label, line.qty));
    }
  }

  final readyLines = b.bom.length - missing.length;
  final pct = b.bom.isEmpty ? 0.0 : (readyLines / b.bom.length).clamp(0.0, 1.0);

  return Readiness(
    buildableQty: missing.isEmpty ? 1 : 0, // demo only
    readyPct: pct,
    shortfalls: missing,
  );
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/data/firestore_streams.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/models/readiness.dart';
import 'package:smd_inv/widgets/boards_list_item.dart';
import '../data/boards_repo.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>; // if you had it elsewhere, reuse

class BoardsPage extends StatelessWidget {
  const BoardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = BoardsRepo();

    return StreamBuilder<List<Doc>>(
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
                  onPressed: () => context.go('/boards/new'),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add your first board'),
                ),
              ],
            ),
          );
        }

        return 
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: boards.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = boards[i];
              final r = _computeReadinessStub(b); // TODO: replace with real inventory math
              return BoardListItem(
                board: b,
                readiness: r,
                onOpen: () => context.go('/boards/${b.id}'),
                onDuplicate: () async {
                  final newId = await repo.duplicateBoard(b.id);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cloned to $newId')));
                },
                onMake: (qty) async {
                  // TODO: call your build/consume flow here
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Make $qty × ${b.name} (stub)')));
                },
              );
            },
          ),
        );
      },
    );
  }
}

// Temporary placeholder until you wire inventory math
Readiness _computeReadinessStub(BoardDoc b) {
  if (b.bom.isEmpty) return const Readiness(buildableQty: 0, readyPct: 0.0, shortfalls: []);
  // Demo: if any line has notes containing "missing", treat as shortfall
  final missing = <Shortfall>[];
  for (final line in b.bom) {
    final ra = line.requiredAttributes;
    final label = [
      if (ra['value'] != null) ra['value'],
      if (ra['size'] != null) ra['size'],
      if (ra['part_type'] != null) ra['part_type'],
      if (ra['part_#'] != null) ra['part_#'],
    ].whereType<String>().join(' ');
    if ((line.notes ?? '').toLowerCase().contains('missing')) {
      missing.add(Shortfall(label.isEmpty ? 'part' : label, line.qty));
    }
  }
  final readyLines = b.bom.length - missing.length;
  final pct = b.bom.isEmpty ? 0.0 : (readyLines / b.bom.length).clamp(0.0, 1.0);
  return Readiness(buildableQty: missing.isEmpty ? 1 : 0, readyPct: pct, shortfalls: missing);
}

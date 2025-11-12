// lib/pages/boards.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/data/unified_firestore_streams.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/models/readiness.dart';
import 'package:smd_inv/widgets/board_card.dart';
import 'package:smd_inv/services/readiness_calculator.dart';
import '../data/boards_repo.dart';
import '../constants/firestore_constants.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class BoardsPage extends StatelessWidget {
  const BoardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = BoardsRepo();

    return StreamBuilder<List<Doc>>(
      stream: collectionStream(FirestoreCollections.boards),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final boards = snap.data!.map(BoardDoc.fromSnap).toList();

        if (boards.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dashboard_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text('No boards yet', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Create a board to track parts and build readiness'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/boards/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Create First Board'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Header with add button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Text('Boards (${boards.length})', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => context.go('/boards/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('New Board'),
                  ),
                ],
              ),
            ),

            // Board grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: boards.length,
                itemBuilder: (context, i) {
                  final b = boards[i];

                  return FutureBuilder<Readiness>(
                    future: ReadinessCalculator.calculate(b),
                    builder: (context, readinessSnap) {
                      final r = readinessSnap.data ?? const Readiness(buildableQty: 0, readyPct: 0.0, shortfalls: []);

                      return ImprovedBoardCard(
                        board: b,
                        readiness: r,
                        onOpen: () => context.go('/boards/${b.id}'),
                        onDuplicate: () async {
                          final newId = await repo.duplicateBoard(b.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Cloned to $newId')));
                          }
                        },
                        onMake: (qty) async {
                          await _makeBoards(context, b, qty);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _makeBoards(BuildContext context, BoardDoc board, int qty) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Make $qty × ${board.name}?'),
            content: Text(
              'This will subtract the required quantities from your inventory.\n\n'
              'This action can be undone from the History page.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
            ],
          ),
    );

    if (confirm != true || !context.mounted) return;

    // Show progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const AlertDialog(
            content: Row(
              children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Subtracting parts from inventory...')],
            ),
          ),
    );

    try {
      // Process each BOM line
      final batch = FirebaseFirestore.instance.batch();

      for (final line in board.bom) {
        final attrs = line.requiredAttributes;
        final requiredQty = line.qty * qty;

        // Find inventory item (same logic as readiness calculator)
        final selectedRef = attrs[FirestoreFields.selectedComponentRef]?.toString();
        if (selectedRef != null && selectedRef.isNotEmpty) {
          final docRef = FirebaseFirestore.instance.collection(FirestoreCollections.inventory).doc(selectedRef);
          batch.update(docRef, {
            FirestoreFields.qty: FieldValue.increment(-requiredQty),
            FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
          });
        }
      }

      // Create history entry
      await FirebaseFirestore.instance.collection(FirestoreCollections.history).add({
        FirestoreFields.action: 'make_board',
        FirestoreFields.boardId: board.id,
        FirestoreFields.boardName: board.name,
        FirestoreFields.quantity: qty,
        FirestoreFields.timestamp: FieldValue.serverTimestamp(),
        FirestoreFields.bomSnapshot: board.bom.map((l) => l.toMap()).toList(),
      });

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Made $qty × ${board.name}'),
            action: SnackBarAction(
              label: 'View History',
              onPressed: () => context.go('/admin'), // Assuming history is in admin
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

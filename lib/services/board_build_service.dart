import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';
import '../models/board.dart';
import 'inventory_matcher.dart';

class BoardBuildService {
  final FirebaseFirestore _db;

  BoardBuildService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<BoardBuildOutcome> makeBoards({
    required BoardDoc board,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      throw const BoardBuildException('Quantity must be greater than zero.');
    }

    final activeLines = board.bom.where((line) => !line.ignored).toList();
    if (activeLines.isEmpty) {
      throw const BoardBuildException('Board has no active BOM lines.');
    }

    final inventory =
        await _db.collection(FirestoreCollections.inventory).get();
    final requiredByDocId = <String, int>{};
    final consumedMetadataByDocId = <String, Map<String, dynamic>>{};
    final unresolved = <String>[];
    final ambiguous = <String>[];

    for (final line in activeLines) {
      final attrs = line.requiredAttributes;
      final needed = line.qty * quantity;
      final matches = await InventoryMatcher.findMatches(
        bomAttributes: attrs,
        inventorySnapshot: inventory,
      );

      if (matches.isEmpty) {
        unresolved.add(InventoryMatcher.makePartLabel(attrs));
        continue;
      }

      QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
      if (matches.length == 1) {
        chosen = matches.first;
      } else {
        final selectedRef =
            attrs[FirestoreFields.selectedComponentRef]?.toString().trim();
        if (selectedRef != null && selectedRef.isNotEmpty) {
          final exact = matches.where((m) => m.id == selectedRef).toList();
          if (exact.length == 1) chosen = exact.first;
        }
        if (chosen == null) {
          ambiguous.add(InventoryMatcher.makePartLabel(attrs));
          continue;
        }
      }

      requiredByDocId[chosen.id] = (requiredByDocId[chosen.id] ?? 0) + needed;
      consumedMetadataByDocId[chosen.id] ??= _snapshotInventoryFields(
        chosen.data(),
      );
    }

    if (unresolved.isNotEmpty || ambiguous.isNotEmpty) {
      final details = <String>[];
      if (unresolved.isNotEmpty) {
        details.add('Unresolved: ${_formatPartList(unresolved)}');
      }
      if (ambiguous.isNotEmpty) {
        details.add('Ambiguous: ${_formatPartList(ambiguous)}');
      }
      throw BoardBuildException(
        'Cannot build until each active BOM line resolves to exactly one inventory item.\n\n${details.join('\n')}',
      );
    }

    if (requiredByDocId.isEmpty) {
      throw const BoardBuildException(
        'No inventory items resolved for this board.',
      );
    }

    final historyRef = _db.collection(FirestoreCollections.history).doc();

    await _db.runTransaction((tx) async {
      for (final entry in requiredByDocId.entries) {
        final docRef = _db
            .collection(FirestoreCollections.inventory)
            .doc(entry.key);
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          throw BoardBuildException(
            'Inventory item no longer exists: ${entry.key}',
          );
        }
        final available =
            (snap.data()?[FirestoreFields.qty] as num?)?.toInt() ?? 0;
        if (available < entry.value) {
          final part =
              snap.data()?[FirestoreFields.partNumber]?.toString() ?? entry.key;
          throw BoardBuildException(
            'Insufficient stock for $part (need ${entry.value}, have $available).',
          );
        }
      }

      for (final entry in requiredByDocId.entries) {
        final docRef = _db
            .collection(FirestoreCollections.inventory)
            .doc(entry.key);
        tx.update(docRef, {
          FirestoreFields.qty: FieldValue.increment(-entry.value),
          FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
        });
      }

      tx.set(historyRef, {
        FirestoreFields.action: 'make_board',
        FirestoreFields.boardId: board.id,
        FirestoreFields.boardName: board.name,
        FirestoreFields.quantity: quantity,
        FirestoreFields.timestamp: FieldValue.serverTimestamp(),
        FirestoreFields.bomSnapshot: board.bom.map((l) => l.toMap()).toList(),
        FirestoreFields.consumedItems:
            requiredByDocId.entries.map((e) {
              final snapshot = consumedMetadataByDocId[e.key] ?? const {};
              return {
                FirestoreFields.docId: e.key,
                FirestoreFields.quantity: e.value,
                ...snapshot,
              };
            }).toList(),
      });
    });

    return BoardBuildOutcome(
      historyId: historyRef.id,
      consumedByDocId: requiredByDocId,
    );
  }

  Future<void> undoMakeHistory(String historyId) async {
    final historyRef = _db
        .collection(FirestoreCollections.history)
        .doc(historyId);

    final historySnap = await historyRef.get();
    if (!historySnap.exists) {
      throw const BoardBuildException('History entry not found.');
    }

    final data = historySnap.data() ?? {};
    if (data[FirestoreFields.action] != 'make_board') {
      throw const BoardBuildException('Only make_board entries can be undone.');
    }
    if (data[FirestoreFields.undoneAt] != null) {
      throw const BoardBuildException('This history entry was already undone.');
    }

    final consumed = (data[FirestoreFields.consumedItems] as List?) ?? const [];
    if (consumed.isEmpty) {
      throw const BoardBuildException(
        'History entry has no consumable item deltas.',
      );
    }

    final ops = <_UndoRestoreOp>[];
    for (final item in consumed) {
      final map = Map<String, dynamic>.from(item as Map);
      final qty = (map[FirestoreFields.quantity] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;

      final docId = _readTrimmedString(map[FirestoreFields.docId]);
      final partNumber = _readTrimmedString(map[FirestoreFields.partNumber]);
      final resolvedRef = await _resolveRestoreRef(
        docId: docId,
        partNumber: partNumber,
      );

      if (resolvedRef != null) {
        ops.add(_UndoRestoreOp.increment(ref: resolvedRef, qty: qty));
      } else {
        final recreateRef =
            docId.isNotEmpty
                ? _db.collection(FirestoreCollections.inventory).doc(docId)
                : _db.collection(FirestoreCollections.inventory).doc();
        ops.add(
          _UndoRestoreOp.recreate(
            ref: recreateRef,
            data: _buildRecreatedInventoryRow(map, restoredQty: qty),
          ),
        );
      }
    }

    if (ops.isEmpty) {
      throw const BoardBuildException(
        'History entry has no valid item deltas to restore.',
      );
    }

    await _db.runTransaction((tx) async {
      final freshHistory = await tx.get(historyRef);
      final freshData = freshHistory.data() ?? {};
      if (freshData[FirestoreFields.undoneAt] != null) {
        throw const BoardBuildException(
          'This history entry was already undone.',
        );
      }

      for (final op in ops) {
        if (op.recreateData != null) {
          tx.set(op.ref, op.recreateData!);
        } else {
          tx.update(op.ref, {
            FirestoreFields.qty: FieldValue.increment(op.qty),
            FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
          });
        }
      }

      tx.update(historyRef, {
        FirestoreFields.undoneAt: FieldValue.serverTimestamp(),
      });
    });
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveRestoreRef({
    required String docId,
    required String partNumber,
  }) async {
    final col = _db.collection(FirestoreCollections.inventory);

    if (docId.isNotEmpty) {
      final byId = await col.doc(docId).get();
      if (byId.exists) return byId.reference;
    }

    if (partNumber.isNotEmpty) {
      final byPart =
          await col
              .where(FirestoreFields.partNumber, isEqualTo: partNumber)
              .limit(2)
              .get();
      if (byPart.docs.length == 1) return byPart.docs.first.reference;
    }

    return null;
  }

  static String _readTrimmedString(dynamic raw) {
    if (raw == null) return '';
    return raw.toString().trim();
  }

  static Map<String, dynamic> _snapshotInventoryFields(
    Map<String, dynamic> src,
  ) {
    return {
      FirestoreFields.partNumber: src[FirestoreFields.partNumber] ?? '',
      FirestoreFields.type: src[FirestoreFields.type] ?? '',
      FirestoreFields.value: src[FirestoreFields.value] ?? '',
      FirestoreFields.package: src[FirestoreFields.package] ?? '',
      FirestoreFields.description: src[FirestoreFields.description] ?? '',
      FirestoreFields.location: src[FirestoreFields.location] ?? '',
      FirestoreFields.pricePerUnit: src[FirestoreFields.pricePerUnit],
      FirestoreFields.notes: src[FirestoreFields.notes] ?? '',
      FirestoreFields.vendorLink: src[FirestoreFields.vendorLink] ?? '',
      FirestoreFields.datasheet: src[FirestoreFields.datasheet] ?? '',
    };
  }

  static Map<String, dynamic> _buildRecreatedInventoryRow(
    Map<String, dynamic> consumedItem, {
    required int restoredQty,
  }) {
    final partNumber = _readTrimmedString(
      consumedItem[FirestoreFields.partNumber],
    );
    return {
      FirestoreFields.partNumber:
          partNumber.isNotEmpty ? partNumber : 'RESTORED_ITEM',
      FirestoreFields.type: _readTrimmedString(
        consumedItem[FirestoreFields.type],
      ),
      FirestoreFields.value: _readTrimmedString(
        consumedItem[FirestoreFields.value],
      ),
      FirestoreFields.package: _readTrimmedString(
        consumedItem[FirestoreFields.package],
      ),
      FirestoreFields.description: _readTrimmedString(
        consumedItem[FirestoreFields.description],
      ),
      FirestoreFields.qty: restoredQty,
      FirestoreFields.location: _readTrimmedString(
        consumedItem[FirestoreFields.location],
      ),
      FirestoreFields.pricePerUnit: _toNum(
        consumedItem[FirestoreFields.pricePerUnit],
      ),
      FirestoreFields.notes: _readTrimmedString(
        consumedItem[FirestoreFields.notes],
      ),
      FirestoreFields.vendorLink: _readTrimmedString(
        consumedItem[FirestoreFields.vendorLink],
      ),
      FirestoreFields.datasheet: _readTrimmedString(
        consumedItem[FirestoreFields.datasheet],
      ),
      FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
    };
  }

  static String _formatPartList(List<String> labels, {int maxItems = 5}) {
    if (labels.length <= maxItems) return labels.join(', ');
    final shown = labels.take(maxItems).join(', ');
    return '$shown, +${labels.length - maxItems} more';
  }

  static num? _toNum(dynamic raw) {
    if (raw is num) return raw;
    final s = _readTrimmedString(raw);
    if (s.isEmpty) return null;
    return num.tryParse(s);
  }
}

class BoardBuildOutcome {
  final String historyId;
  final Map<String, int> consumedByDocId;

  const BoardBuildOutcome({
    required this.historyId,
    required this.consumedByDocId,
  });
}

class BoardBuildException implements Exception {
  final String message;

  const BoardBuildException(this.message);
}

class _UndoRestoreOp {
  final DocumentReference<Map<String, dynamic>> ref;
  final int qty;
  final Map<String, dynamic>? recreateData;

  const _UndoRestoreOp._({
    required this.ref,
    required this.qty,
    required this.recreateData,
  });

  factory _UndoRestoreOp.increment({
    required DocumentReference<Map<String, dynamic>> ref,
    required int qty,
  }) {
    return _UndoRestoreOp._(ref: ref, qty: qty, recreateData: null);
  }

  factory _UndoRestoreOp.recreate({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
  }) {
    return _UndoRestoreOp._(ref: ref, qty: 0, recreateData: data);
  }
}

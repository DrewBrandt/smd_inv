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
    Map<int, BoardBuildLineSelection> lineSelections = const {},
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
  }) async {
    if (quantity <= 0) {
      throw const BoardBuildException('Quantity must be greater than zero.');
    }

    final activeEntries =
        board.bom
            .asMap()
            .entries
            .where((entry) => !entry.value.ignored)
            .toList();
    if (activeEntries.isEmpty) {
      throw const BoardBuildException('Board has no active BOM lines.');
    }

    final preview = await previewBuild(
      board: board,
      quantity: quantity,
      lineSelections: lineSelections,
      inventorySnapshot: inventorySnapshot,
    );
    if (preview.issues.isNotEmpty) {
      throw BoardBuildException(_formatIssuesMessage(preview.issues));
    }

    final requiredByDocId = preview.consumedByDocId;
    final consumedMetadataByDocId = preview.consumedMetadataByDocId;
    if (requiredByDocId.isEmpty && preview.skippedLines.isEmpty) {
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
        FirestoreFields.skippedLines:
            preview.skippedLines.map((line) => line.toMap()).toList(),
      });
    });

    return BoardBuildOutcome(
      historyId: historyRef.id,
      consumedByDocId: requiredByDocId,
    );
  }

  Future<BoardBuildPreview> previewBuild({
    required BoardDoc board,
    required int quantity,
    Map<int, BoardBuildLineSelection> lineSelections = const {},
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
  }) async {
    if (quantity <= 0) {
      throw const BoardBuildException('Quantity must be greater than zero.');
    }

    final activeEntries =
        board.bom
            .asMap()
            .entries
            .where((entry) => !entry.value.ignored)
            .toList();
    if (activeEntries.isEmpty) {
      return const BoardBuildPreview(
        consumedByDocId: {},
        consumedMetadataByDocId: {},
        issues: [],
        skippedLines: [],
      );
    }

    final inventory =
        inventorySnapshot ??
        await _db.collection(FirestoreCollections.inventory).get();
    final matcherIndex = InventoryMatcherIndex.fromSnapshot(inventory);
    final requiredByDocId = <String, int>{};
    final consumedMetadataByDocId = <String, Map<String, dynamic>>{};
    final issues = <BoardBuildIssue>[];
    final skippedLines = <BoardBuildSkippedLine>[];

    for (final entry in activeEntries) {
      final lineIndex = entry.key;
      final line = entry.value;
      final attrs = line.requiredAttributes;
      final needed = line.qty * quantity;
      final label = InventoryMatcher.makePartLabel(attrs);
      final selection = lineSelections[lineIndex];

      if (selection?.skip == true) {
        skippedLines.add(
          BoardBuildSkippedLine(
            lineIndex: lineIndex,
            designators: line.designators,
            partLabel: label,
            requiredQty: needed,
          ),
        );
        continue;
      }

      QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
      var matches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final manualDocId = selection?.inventoryDocId?.trim();

      if (manualDocId != null && manualDocId.isNotEmpty) {
        chosen = _findDocById(inventory, manualDocId);
        if (chosen == null) {
          issues.add(
            BoardBuildIssue(
              kind: BoardBuildIssueKind.unresolved,
              lineIndex: lineIndex,
              line: line,
              partLabel: label,
              requiredQty: needed,
              candidates: const [],
              selectedDocId: manualDocId,
              availableQty: 0,
            ),
          );
          continue;
        }
      } else {
        matches = InventoryMatcher.findMatchesSync(
          bomAttributes: attrs,
          matcherIndex: matcherIndex,
        );

        if (matches.isEmpty) {
          issues.add(
            BoardBuildIssue(
              kind: BoardBuildIssueKind.unresolved,
              lineIndex: lineIndex,
              line: line,
              partLabel: label,
              requiredQty: needed,
              candidates: const [],
              selectedDocId: null,
              availableQty: 0,
            ),
          );
          continue;
        }

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
            issues.add(
              BoardBuildIssue(
                kind: BoardBuildIssueKind.ambiguous,
                lineIndex: lineIndex,
                line: line,
                partLabel: label,
                requiredQty: needed,
                candidates: matches,
                selectedDocId: selectedRef,
                availableQty: 0,
              ),
            );
            continue;
          }
        }
      }

      final availableQty =
          (chosen.data()[FirestoreFields.qty] as num?)?.toInt() ?? 0;
      if (availableQty < needed) {
        issues.add(
          BoardBuildIssue(
            kind: BoardBuildIssueKind.insufficientStock,
            lineIndex: lineIndex,
            line: line,
            partLabel: label,
            requiredQty: needed,
            candidates: matches,
            selectedDocId: chosen.id,
            availableQty: availableQty,
          ),
        );
        continue;
      }

      requiredByDocId[chosen.id] = (requiredByDocId[chosen.id] ?? 0) + needed;
      consumedMetadataByDocId[chosen.id] ??= _snapshotInventoryFields(
        chosen.data(),
      );
    }

    return BoardBuildPreview(
      consumedByDocId: requiredByDocId,
      consumedMetadataByDocId: consumedMetadataByDocId,
      issues: issues,
      skippedLines: skippedLines,
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

    if (ops.isEmpty && consumed.isNotEmpty) {
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

  static String _formatIssuesMessage(List<BoardBuildIssue> issues) {
    final unresolved =
        issues
            .where((issue) => issue.kind == BoardBuildIssueKind.unresolved)
            .map((issue) => issue.partLabel)
            .toList();
    final ambiguous =
        issues
            .where((issue) => issue.kind == BoardBuildIssueKind.ambiguous)
            .map((issue) => issue.partLabel)
            .toList();
    final insufficient =
        issues
            .where(
              (issue) => issue.kind == BoardBuildIssueKind.insufficientStock,
            )
            .map(
              (issue) =>
                  '${issue.partLabel} (${issue.availableQty}/${issue.requiredQty})',
            )
            .toList();

    final details = <String>[];
    if (unresolved.isNotEmpty) {
      details.add('Unresolved: ${_formatPartList(unresolved)}');
    }
    if (ambiguous.isNotEmpty) {
      details.add('Ambiguous: ${_formatPartList(ambiguous)}');
    }
    if (insufficient.isNotEmpty) {
      details.add('Insufficient stock: ${_formatPartList(insufficient)}');
    }

    return 'Cannot build until each active BOM line resolves to exactly one inventory item, or is skipped.\n\n${details.join('\n')}';
  }

  static QueryDocumentSnapshot<Map<String, dynamic>>? _findDocById(
    QuerySnapshot<Map<String, dynamic>> inventory,
    String docId,
  ) {
    for (final doc in inventory.docs) {
      if (doc.id == docId) return doc;
    }
    return null;
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

class BoardBuildPreview {
  final Map<String, int> consumedByDocId;
  final Map<String, Map<String, dynamic>> consumedMetadataByDocId;
  final List<BoardBuildIssue> issues;
  final List<BoardBuildSkippedLine> skippedLines;

  const BoardBuildPreview({
    required this.consumedByDocId,
    required this.consumedMetadataByDocId,
    required this.issues,
    required this.skippedLines,
  });
}

class BoardBuildLineSelection {
  final String? inventoryDocId;
  final bool skip;

  const BoardBuildLineSelection({this.inventoryDocId, this.skip = false});

  BoardBuildLineSelection copyWith({String? inventoryDocId, bool? skip}) {
    return BoardBuildLineSelection(
      inventoryDocId: inventoryDocId,
      skip: skip ?? this.skip,
    );
  }
}

class BoardBuildSkippedLine {
  final int lineIndex;
  final String designators;
  final String partLabel;
  final int requiredQty;

  const BoardBuildSkippedLine({
    required this.lineIndex,
    required this.designators,
    required this.partLabel,
    required this.requiredQty,
  });

  Map<String, dynamic> toMap() {
    return {
      'line_index': lineIndex,
      'designators': designators,
      'part_label': partLabel,
      'required_qty': requiredQty,
    };
  }
}

class BoardBuildIssue {
  final BoardBuildIssueKind kind;
  final int lineIndex;
  final BomLine line;
  final String partLabel;
  final int requiredQty;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> candidates;
  final String? selectedDocId;
  final int availableQty;

  const BoardBuildIssue({
    required this.kind,
    required this.lineIndex,
    required this.line,
    required this.partLabel,
    required this.requiredQty,
    required this.candidates,
    required this.selectedDocId,
    required this.availableQty,
  });
}

enum BoardBuildIssueKind { unresolved, ambiguous, insufficientStock }

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

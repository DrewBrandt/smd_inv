// lib/services/inventory_history_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';

/// Records and undoes inventory-level history events:
/// edit_item, delete_item, add_item, import_csv.
class InventoryHistoryService {
  final FirebaseFirestore _db;

  InventoryHistoryService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // ── Recording ──────────────────────────────────────────────────────────────

  Future<void> recordEdit({
    required String docId,
    required String fieldPath,
    required dynamic oldValue,
    required dynamic newValue,
    required Map<String, dynamic> itemSnapshot,
  }) async {
    await _db.collection(FirestoreCollections.history).add({
      FirestoreFields.action: HistoryActions.editItem,
      FirestoreFields.docId: docId,
      FirestoreFields.editedField: fieldPath,
      FirestoreFields.oldValue: oldValue,
      FirestoreFields.newValue: newValue,
      FirestoreFields.itemSnapshot: itemSnapshot,
      FirestoreFields.timestamp: FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordDelete({
    required String docId,
    required Map<String, dynamic> itemSnapshot,
  }) async {
    await _db.collection(FirestoreCollections.history).add({
      FirestoreFields.action: HistoryActions.deleteItem,
      FirestoreFields.docId: docId,
      FirestoreFields.itemSnapshot: itemSnapshot,
      FirestoreFields.timestamp: FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordAdd({
    required String docId,
    required Map<String, dynamic> itemSnapshot,
  }) async {
    await _db.collection(FirestoreCollections.history).add({
      FirestoreFields.action: HistoryActions.addItem,
      FirestoreFields.docId: docId,
      FirestoreFields.itemSnapshot: itemSnapshot,
      FirestoreFields.timestamp: FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordImport({
    required List<ImportedItemRecord> addedItems,
    required List<UpdatedItemRecord> updatedItems,
  }) async {
    if (addedItems.isEmpty && updatedItems.isEmpty) return;

    await _db.collection(FirestoreCollections.history).add({
      FirestoreFields.action: HistoryActions.importCsv,
      FirestoreFields.itemCount: addedItems.length + updatedItems.length,
      FirestoreFields.addedItems:
          addedItems
              .map((e) => {
                FirestoreFields.docId: e.docId,
                FirestoreFields.itemSnapshot: e.snapshot,
              })
              .toList(),
      FirestoreFields.updatedItems:
          updatedItems
              .map((e) => {
                FirestoreFields.docId: e.docId,
                FirestoreFields.importAction: e.importAction,
                FirestoreFields.oldSnapshot: e.oldSnapshot,
                FirestoreFields.newSnapshot: e.newSnapshot,
              })
              .toList(),
      FirestoreFields.timestamp: FieldValue.serverTimestamp(),
    });
  }

  // ── Undoing ────────────────────────────────────────────────────────────────

  Future<void> undo(String historyId) async {
    final ref = _db.collection(FirestoreCollections.history).doc(historyId);
    final snap = await ref.get();

    if (!snap.exists) {
      throw const InventoryHistoryException('History entry not found.');
    }

    final data = snap.data() ?? {};
    if (data[FirestoreFields.undoneAt] != null) {
      throw const InventoryHistoryException(
        'This history entry was already undone.',
      );
    }

    final action = data[FirestoreFields.action]?.toString() ?? '';
    switch (action) {
      case HistoryActions.editItem:
        await _undoEdit(ref, data);
      case HistoryActions.deleteItem:
        await _undoDelete(ref, data);
      case HistoryActions.addItem:
        await _undoAdd(ref, data);
      case HistoryActions.importCsv:
        await _undoImport(ref, data);
      default:
        throw InventoryHistoryException('Unknown action type: $action');
    }
  }

  Future<void> _undoEdit(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final docId = _str(data[FirestoreFields.docId]);
    final fieldPath = _str(data[FirestoreFields.editedField]);
    final oldValue = data[FirestoreFields.oldValue];

    if (docId.isEmpty || fieldPath.isEmpty) {
      throw const InventoryHistoryException('Corrupt edit history entry.');
    }

    final docRef = _db.collection(FirestoreCollections.inventory).doc(docId);

    await _db.runTransaction((tx) async {
      final fresh = await tx.get(ref);
      if ((fresh.data() ?? {})[FirestoreFields.undoneAt] != null) {
        throw const InventoryHistoryException('Already undone.');
      }

      tx.update(docRef, {
        fieldPath: oldValue,
        FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
      });
      tx.update(ref, {FirestoreFields.undoneAt: FieldValue.serverTimestamp()});
    });
  }

  Future<void> _undoDelete(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final docId = _str(data[FirestoreFields.docId]);
    final snapshot = Map<String, dynamic>.from(
      data[FirestoreFields.itemSnapshot] as Map? ?? {},
    );

    if (docId.isEmpty) {
      throw const InventoryHistoryException('Corrupt delete history entry.');
    }

    final docRef = _db.collection(FirestoreCollections.inventory).doc(docId);

    await _db.runTransaction((tx) async {
      final fresh = await tx.get(ref);
      if ((fresh.data() ?? {})[FirestoreFields.undoneAt] != null) {
        throw const InventoryHistoryException('Already undone.');
      }

      tx.set(docRef, {
        ...snapshot,
        FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
      });
      tx.update(ref, {FirestoreFields.undoneAt: FieldValue.serverTimestamp()});
    });
  }

  Future<void> _undoAdd(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final docId = _str(data[FirestoreFields.docId]);

    if (docId.isEmpty) {
      throw const InventoryHistoryException('Corrupt add history entry.');
    }

    final docRef = _db.collection(FirestoreCollections.inventory).doc(docId);

    await _db.runTransaction((tx) async {
      final fresh = await tx.get(ref);
      if ((fresh.data() ?? {})[FirestoreFields.undoneAt] != null) {
        throw const InventoryHistoryException('Already undone.');
      }

      tx.delete(docRef);
      tx.update(ref, {FirestoreFields.undoneAt: FieldValue.serverTimestamp()});
    });
  }

  Future<void> _undoImport(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final addedItems = (data[FirestoreFields.addedItems] as List?) ?? const [];
    final updatedItems =
        (data[FirestoreFields.updatedItems] as List?) ?? const [];

    final toDelete = <DocumentReference<Map<String, dynamic>>>[];
    final toRestore =
        <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>[];

    for (final item in addedItems) {
      final map = Map<String, dynamic>.from(item as Map);
      final docId = _str(map[FirestoreFields.docId]);
      if (docId.isEmpty) continue;
      toDelete.add(_db.collection(FirestoreCollections.inventory).doc(docId));
    }

    for (final item in updatedItems) {
      final map = Map<String, dynamic>.from(item as Map);
      final docId = _str(map[FirestoreFields.docId]);
      if (docId.isEmpty) continue;
      final oldSnapshot = Map<String, dynamic>.from(
        map[FirestoreFields.oldSnapshot] as Map? ?? {},
      );
      toRestore.add((
        _db.collection(FirestoreCollections.inventory).doc(docId),
        oldSnapshot,
      ));
    }

    await _db.runTransaction((tx) async {
      final fresh = await tx.get(ref);
      if ((fresh.data() ?? {})[FirestoreFields.undoneAt] != null) {
        throw const InventoryHistoryException('Already undone.');
      }

      for (final docRef in toDelete) {
        tx.delete(docRef);
      }
      for (final (docRef, snapshot) in toRestore) {
        tx.set(docRef, {
          ...snapshot,
          FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
        });
      }

      tx.update(ref, {FirestoreFields.undoneAt: FieldValue.serverTimestamp()});
    });
  }

  static String _str(dynamic raw) => raw?.toString().trim() ?? '';
}

// ── Data classes for recordImport ──────────────────────────────────────────

class ImportedItemRecord {
  final String docId;
  final Map<String, dynamic> snapshot;

  const ImportedItemRecord({required this.docId, required this.snapshot});
}

class UpdatedItemRecord {
  final String docId;

  /// 'add_qty' or 'replace'
  final String importAction;
  final Map<String, dynamic> oldSnapshot;
  final Map<String, dynamic> newSnapshot;

  const UpdatedItemRecord({
    required this.docId,
    required this.importAction,
    required this.oldSnapshot,
    required this.newSnapshot,
  });
}

class InventoryHistoryException implements Exception {
  final String message;

  const InventoryHistoryException(this.message);
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';

class BoardsRepo {
  final FirebaseFirestore _db;

  BoardsRepo({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestoreCollections.boards);

  Future<String> duplicateBoard(String sourceId, {String? newName}) async {
    final srcRef = _col.doc(sourceId);
    final snap = await srcRef.get();
    if (!snap.exists) throw StateError('Board $sourceId not found');

    final data = Map<String, dynamic>.from(snap.data()!);
    data[FirestoreFields.name] =
        newName ?? '${data[FirestoreFields.name]} (copy)';
    data[FirestoreFields.createdAt] = FieldValue.serverTimestamp();
    data[FirestoreFields.updatedAt] = FieldValue.serverTimestamp();

    final dstRef = _col.doc();
    await dstRef.set(data);
    return dstRef.id;
  }

  Future<void> deleteBoard(String id) async {
    await _col.doc(id).delete();
  }

  // handy later:
  Future<void> touchUpdatedAt(String id) => _col.doc(id).update({
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
  });
}

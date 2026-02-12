import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/data/boards_repo.dart';

void main() {
  group('BoardsRepo', () {
    late FakeFirebaseFirestore db;
    late BoardsRepo repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = BoardsRepo(firestore: db);
    });

    test('duplicateBoard creates copy with default name suffix', () async {
      final srcRef = await db.collection(FirestoreCollections.boards).add({
        FirestoreFields.name: 'Main Board',
        FirestoreFields.bom: const [],
      });

      final newId = await repo.duplicateBoard(srcRef.id);

      final all = await db.collection(FirestoreCollections.boards).get();
      expect(all.docs, hasLength(2));
      final clone = all.docs.firstWhere((d) => d.id == newId).data();
      expect(clone[FirestoreFields.name], 'Main Board (copy)');
    });

    test('duplicateBoard uses custom name when provided', () async {
      final srcRef = await db.collection(FirestoreCollections.boards).add({
        FirestoreFields.name: 'Original',
        FirestoreFields.bom: const [],
      });

      final newId = await repo.duplicateBoard(srcRef.id, newName: 'Rev B');
      final clone =
          await db.collection(FirestoreCollections.boards).doc(newId).get();

      expect(clone.exists, isTrue);
      expect(clone.data()?[FirestoreFields.name], 'Rev B');
    });

    test('deleteBoard removes board document', () async {
      final ref = await db.collection(FirestoreCollections.boards).add({
        FirestoreFields.name: 'Delete me',
        FirestoreFields.bom: const [],
      });

      await repo.deleteBoard(ref.id);
      final snap =
          await db.collection(FirestoreCollections.boards).doc(ref.id).get();
      expect(snap.exists, isFalse);
    });

    test('duplicateBoard throws when source board is missing', () async {
      await expectLater(
        repo.duplicateBoard('missing-id'),
        throwsA(isA<StateError>()),
      );
    });

    test('touchUpdatedAt writes server timestamp field', () async {
      final ref = await db.collection(FirestoreCollections.boards).add({
        FirestoreFields.name: 'Touch me',
        FirestoreFields.bom: const [],
      });

      await repo.touchUpdatedAt(ref.id);
      final snap =
          await db.collection(FirestoreCollections.boards).doc(ref.id).get();
      expect(snap.data()!.containsKey(FirestoreFields.updatedAt), isTrue);
    });
  });
}

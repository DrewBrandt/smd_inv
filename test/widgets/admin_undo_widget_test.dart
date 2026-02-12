import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/pages/admin.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/services/board_build_service.dart';
import 'package:smd_inv/services/inventory_audit_service.dart';

void main() {
  setUp(() {
    AuthService.canEditOverride = (_) => true;
  });

  tearDown(() {
    AuthService.canEditOverride = null;
  });

  testWidgets('Admin undo button restores inventory and marks history undone', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final invRef = await db.collection(FirestoreCollections.inventory).add({
      FirestoreFields.partNumber: 'R-10K',
      FirestoreFields.qty: 10,
    });

    await db.collection(FirestoreCollections.history).add({
      FirestoreFields.action: 'make_board',
      FirestoreFields.boardName: 'Main',
      FirestoreFields.quantity: 1,
      FirestoreFields.timestamp: Timestamp.now(),
      FirestoreFields.consumedItems: [
        {'doc_id': invRef.id, FirestoreFields.quantity: 3},
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminPage(
            firestore: db,
            buildService: BoardBuildService(firestore: db),
            auditService: InventoryAuditService(firestore: db),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final invAfter = await invRef.get();
    expect(invAfter.data()?[FirestoreFields.qty], 13);

    final historySnap = await db.collection(FirestoreCollections.history).get();
    expect(historySnap.docs.single.data()[FirestoreFields.undoneAt], isNotNull);
  });
}

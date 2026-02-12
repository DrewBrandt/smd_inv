import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/services/inventory_audit_service.dart';

void main() {
  group('InventoryAuditService', () {
    late FakeFirebaseFirestore db;
    late InventoryAuditService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = InventoryAuditService(firestore: db);
    });

    test('exportInventoryCsv exports header and items', () async {
      await db.collection(FirestoreCollections.inventory).doc('inv-r10k').set({
        FirestoreFields.partNumber: 'R-10K',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 200,
      });

      final csv = await service.exportInventoryCsv();
      expect(csv, contains(FirestoreFields.docId));
      expect(csv, contains('inv-r10k'));
      expect(csv, contains(FirestoreFields.partNumber));
      expect(csv, contains('R-10K'));
      expect(csv, contains('resistor'));
    });

    test(
      'replaceInventoryFromCsvText preserves doc_id rows and replaces rest',
      () async {
        await db.collection(FirestoreCollections.inventory).doc('keep-me').set({
          FirestoreFields.partNumber: 'OLD-1',
          FirestoreFields.type: 'ic',
          FirestoreFields.qty: 5,
        });
        await db
            .collection(FirestoreCollections.inventory)
            .doc('delete-me')
            .set({
              FirestoreFields.partNumber: 'OLD-1',
              FirestoreFields.type: 'ic',
              FirestoreFields.qty: 5,
            });

        const csv = '''
doc_id,part_#,type,value,package,description,qty,location,price_per_unit,notes,vendor_link,datasheet
keep-me,R-1K,resistor,1k,0603,Resistor 1k,100,Drawer A,0.01,,,
,C-100N,capacitor,100n,0603,Cap 100n,50,Drawer B,0.02,,,
''';

        final result = await service.replaceInventoryFromCsvText(csv);
        expect(result.previousCount, 2);
        expect(result.importedCount, 2);

        final inv = await db.collection(FirestoreCollections.inventory).get();
        expect(inv.docs.length, 2);
        expect(inv.docs.any((d) => d.id == 'keep-me'), true);
        expect(inv.docs.any((d) => d.id == 'delete-me'), false);
        expect(
          inv.docs.any((d) => d.data()[FirestoreFields.partNumber] == 'R-1K'),
          true,
        );
        expect(
          inv.docs.any((d) => d.data()[FirestoreFields.partNumber] == 'C-100N'),
          true,
        );
      },
    );

    test('replaceInventoryFromCsvText rejects duplicate doc_id rows', () async {
      const csv = '''
doc_id,part_#,type,qty
dup-id,R-1K,resistor,10
dup-id,C-100N,capacitor,20
''';

      expect(
        () => service.replaceInventoryFromCsvText(csv),
        throwsA(isA<AuditReplaceException>()),
      );
    });
  });
}

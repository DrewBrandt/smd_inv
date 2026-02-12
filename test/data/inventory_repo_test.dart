import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/data/inventory_repo.dart';

void main() {
  group('InventoryRepo', () {
    late FakeFirebaseFirestore db;
    late InventoryRepo repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = InventoryRepo(firestore: db);
    });

    Future<void> seedInventory() async {
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'C-100N',
        FirestoreFields.type: 'capacitor',
        FirestoreFields.package: '0603',
        FirestoreFields.location: 'A1',
        FirestoreFields.qty: 10,
      });
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-10K',
        FirestoreFields.type: 'resistor',
        FirestoreFields.package: '0805',
        FirestoreFields.location: 'B2',
        FirestoreFields.qty: 25,
      });
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-1K',
        FirestoreFields.type: 'resistor',
        FirestoreFields.package: '0603',
        FirestoreFields.location: 'A1',
        FirestoreFields.qty: 5,
      });
    }

    test('streamAll returns ordered docs and supports type filter', () async {
      await seedInventory();

      final all = await repo.streamAll().first;
      expect(all, hasLength(3));
      expect(all.map((d) => d.data()[FirestoreFields.type]).toList(), [
        'capacitor',
        'resistor',
        'resistor',
      ]);

      final onlyResistors =
          await repo.streamAll(typeFilter: ['resistor']).first;
      expect(onlyResistors, hasLength(2));
      expect(
        onlyResistors.every(
          (d) => d.data()[FirestoreFields.type] == 'resistor',
        ),
        isTrue,
      );
    });

    test('streamFiltered applies package and location filters', () async {
      await seedInventory();

      final filtered =
          await repo
              .streamFiltered(
                typeFilter: ['resistor'],
                packageFilter: ['0603'],
                locationFilter: ['A1'],
              )
              .first;

      expect(filtered, hasLength(1));
      expect(filtered.single.data()[FirestoreFields.partNumber], 'R-1K');
    });

    test('streamCollection streams arbitrary collection snapshots', () async {
      await db.collection('custom').add({'name': 'x'});
      await db.collection('custom').add({'name': 'y'});

      final docs = await repo.streamCollection('custom').first;
      expect(docs, hasLength(2));
      expect(docs.map((d) => d.data()['name']), containsAll(['x', 'y']));
    });

    test(
      'create/getById/updateField/adjustQuantity/delete roundtrip',
      () async {
        final id = await repo.create({
          FirestoreFields.partNumber: 'U-MCU',
          FirestoreFields.type: 'ic',
          FirestoreFields.qty: 7,
        });

        final created = await repo.getById(id);
        expect(created.exists, isTrue);
        expect(created.data(), contains(FirestoreFields.createdAt));
        expect(created.data(), contains(FirestoreFields.lastUpdated));

        await repo.updateField(id, FirestoreFields.location, 'C3');
        final afterUpdate = await repo.getById(id);
        expect(afterUpdate.data()?[FirestoreFields.location], 'C3');
        expect(afterUpdate.data(), contains(FirestoreFields.lastUpdated));

        await repo.adjustQuantity(id, 5);
        final afterAdjust = await repo.getById(id);
        expect(afterAdjust.data()?[FirestoreFields.qty], 12);

        await repo.delete(id);
        final afterDelete = await repo.getById(id);
        expect(afterDelete.exists, isFalse);
      },
    );
  });
}

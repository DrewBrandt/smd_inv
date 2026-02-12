import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/data/firebase_datagrid_source.dart';
import 'package:smd_inv/models/columns.dart';

void main() {
  group('FirestoreDataSource', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    Future<FirestoreDataSource> makeSource({
      required List<ColumnSpec> columns,
      required List<Map<String, dynamic>> docs,
    }) async {
      for (final doc in docs) {
        await db.collection('inventory').add(doc);
      }
      final snap = await db.collection('inventory').get();
      return FirestoreDataSource(
        docs: snap.docs,
        columns: columns,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      );
    }

    test('rowCount/docAt/getRowData expose underlying docs', () async {
      final source = await makeSource(
        columns: [ColumnSpec(field: 'type')],
        docs: [
          {'type': 'resistor'},
          {'type': 'ic'},
        ],
      );

      expect(source.rowCount, 2);
      expect(source.docAt(0).id, isNotEmpty);
      expect(source.getRowData(1)['type'], 'ic');
    });

    test('buildRowForIndex formats type column values', () async {
      final source = await makeSource(
        columns: [ColumnSpec(field: 'type')],
        docs: [
          {'type': 'ic'},
          {'type': 'resistor'},
        ],
      );

      final row0 = source.buildRowForIndex(0);
      final row1 = source.buildRowForIndex(1);
      expect(row0.getCells().single.value, 'IC');
      expect(row1.getCells().single.value, 'Resistor');
    });

    test('onCommitValue updates firestore and local nested map', () async {
      final source = await makeSource(
        columns: [ColumnSpec(field: 'meta.level')],
        docs: [
          {
            'type': 'capacitor',
            'meta': {'level': 'old'},
          },
        ],
      );

      await source.onCommitValue(0, 'meta.level', 'new');

      final docRef = source.docAt(0).reference;
      final fresh = await docRef.get();
      final freshData = fresh.data() ?? {};
      final nested =
          (freshData['meta'] as Map<String, dynamic>?)?['level']?.toString();
      final dotted = freshData['meta.level']?.toString();
      expect(nested == 'new' || dotted == 'new', isTrue);
    });

    test('deleteAt removes the document and shrinks rowCount', () async {
      final source = await makeSource(
        columns: [ColumnSpec(field: 'part_#')],
        docs: [
          {'part_#': 'A'},
          {'part_#': 'B'},
        ],
      );

      final toDeleteId = source.docAt(0).id;
      await source.deleteAt(0);

      expect(source.rowCount, 1);
      final remaining = await db.collection('inventory').get();
      expect(remaining.docs.map((d) => d.id), isNot(contains(toDeleteId)));
    });
  });
}

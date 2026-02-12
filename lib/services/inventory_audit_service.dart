import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import '../constants/firestore_constants.dart';
import 'csv_parser_service.dart';

class InventoryAuditService {
  final FirebaseFirestore _db;

  InventoryAuditService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<String> exportInventoryCsv() async {
    final snap =
        await _db
            .collection(FirestoreCollections.inventory)
            .orderBy(FirestoreFields.partNumber)
            .get();

    final rows = <List<dynamic>>[
      [
        FirestoreFields.docId,
        FirestoreFields.partNumber,
        FirestoreFields.type,
        FirestoreFields.value,
        FirestoreFields.package,
        FirestoreFields.description,
        FirestoreFields.qty,
        FirestoreFields.location,
        FirestoreFields.pricePerUnit,
        FirestoreFields.notes,
        FirestoreFields.vendorLink,
        FirestoreFields.datasheet,
      ],
    ];

    for (final doc in snap.docs) {
      final d = doc.data();
      rows.add([
        doc.id,
        d[FirestoreFields.partNumber] ?? '',
        d[FirestoreFields.type] ?? '',
        d[FirestoreFields.value] ?? '',
        d[FirestoreFields.package] ?? '',
        d[FirestoreFields.description] ?? '',
        d[FirestoreFields.qty] ?? 0,
        d[FirestoreFields.location] ?? '',
        d[FirestoreFields.pricePerUnit] ?? '',
        d[FirestoreFields.notes] ?? '',
        d[FirestoreFields.vendorLink] ?? '',
        d[FirestoreFields.datasheet] ?? '',
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  Future<AuditReplaceResult> replaceInventoryFromCsvText(String csvText) async {
    final parseResult = CsvParserService.parse(
      csvText,
      expectedColumns: const [
        'doc_id',
        'Document ID',
        'ID',
        'part_#',
        'Part #',
        'type',
        'Type',
        'value',
        'Value',
        'package',
        'Package',
        'description',
        'Description',
        'qty',
        'Qty',
        'location',
        'Location',
        'price_per_unit',
        'Price',
        'notes',
        'Notes',
        'vendor_link',
        'Vendor',
        'datasheet',
        'Datasheet',
      ],
    );

    if (!parseResult.success) {
      throw AuditReplaceException(parseResult.error ?? 'Failed to parse CSV.');
    }

    final replacementItems = <_AuditReplacementItem>[];
    final seenDocIds = <String>{};
    int skipped = 0;

    for (final row in parseResult.dataRows) {
      final docId = _cell(parseResult, row, const [
        FirestoreFields.docId,
        'Document ID',
        'ID',
      ]);
      final partNumber = _cell(parseResult, row, [
        FirestoreFields.partNumber,
        'Part #',
      ]);
      if (partNumber.isEmpty) {
        skipped++;
        continue;
      }

      if (docId.isNotEmpty && !seenDocIds.add(docId)) {
        throw AuditReplaceException(
          'CSV contains duplicate doc_id value: $docId',
        );
      }

      final qty =
          int.tryParse(_cell(parseResult, row, [FirestoreFields.qty, 'Qty'])) ??
          0;
      final priceRaw = _cell(parseResult, row, [
        FirestoreFields.pricePerUnit,
        'Price',
      ]);
      final price = double.tryParse(priceRaw.replaceAll(RegExp(r'[^\d.]'), ''));

      replacementItems.add(
        _AuditReplacementItem(
          docId: docId,
          data: {
            FirestoreFields.partNumber: partNumber,
            FirestoreFields.type: _cell(parseResult, row, [
              FirestoreFields.type,
              'Type',
            ]),
            FirestoreFields.value: _cell(parseResult, row, [
              FirestoreFields.value,
              'Value',
            ]),
            FirestoreFields.package: _cell(parseResult, row, [
              FirestoreFields.package,
              'Package',
            ]),
            FirestoreFields.description: _cell(parseResult, row, [
              FirestoreFields.description,
              'Description',
            ]),
            FirestoreFields.qty: qty,
            FirestoreFields.location: _cell(parseResult, row, [
              FirestoreFields.location,
              'Location',
            ]),
            FirestoreFields.pricePerUnit: price,
            FirestoreFields.notes: _cell(parseResult, row, [
              FirestoreFields.notes,
              'Notes',
            ]),
            FirestoreFields.vendorLink: _cell(parseResult, row, [
              FirestoreFields.vendorLink,
              'Vendor',
            ]),
            FirestoreFields.datasheet: _cell(parseResult, row, [
              FirestoreFields.datasheet,
              'Datasheet',
            ]),
            FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
          },
        ),
      );
    }

    final oldSnap = await _db.collection(FirestoreCollections.inventory).get();
    final oldCount = oldSnap.docs.length;
    await _replaceAll(oldSnap.docs, replacementItems);

    return AuditReplaceResult(
      previousCount: oldCount,
      importedCount: replacementItems.length,
      skippedRows: skipped,
    );
  }

  Future<void> _replaceAll(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> existingDocs,
    List<_AuditReplacementItem> replacementItems,
  ) async {
    // Upsert replacement rows first, then delete stale rows.
    // This order is safer than delete-first if import fails mid-way.
    WriteBatch batch = _db.batch();
    int opCount = 0;
    final targetIds = <String>{};

    Future<void> flush() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = _db.batch();
      opCount = 0;
    }

    for (final item in replacementItems) {
      final targetId =
          item.docId.isNotEmpty
              ? item.docId
              : _db.collection(FirestoreCollections.inventory).doc().id;
      targetIds.add(targetId);
      final ref = _db.collection(FirestoreCollections.inventory).doc(targetId);
      batch.set(ref, item.data);
      opCount++;
      if (opCount >= 400) await flush();
    }

    for (final doc in existingDocs) {
      if (targetIds.contains(doc.id)) continue;
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 400) await flush();
    }

    await flush();
  }

  static String _cell(
    CsvParseResult parseResult,
    List<dynamic> row,
    List<String> aliases,
  ) {
    for (final alias in aliases) {
      final value = parseResult.getCellValue(row, alias).trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

class AuditReplaceResult {
  final int previousCount;
  final int importedCount;
  final int skippedRows;

  const AuditReplaceResult({
    required this.previousCount,
    required this.importedCount,
    required this.skippedRows,
  });
}

class AuditReplaceException implements Exception {
  final String message;

  const AuditReplaceException(this.message);
}

class _AuditReplacementItem {
  final String docId;
  final Map<String, dynamic> data;

  const _AuditReplacementItem({required this.docId, required this.data});
}

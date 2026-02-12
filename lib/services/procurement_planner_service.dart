import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_constants.dart';
import '../models/procurement.dart';
import 'inventory_matcher.dart';
import 'part_normalizer.dart';

class ProcurementPlannerService {
  final FirebaseFirestore _db;

  ProcurementPlannerService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<ProcurementPlan> buildPlan({
    required List<BoardOrderRequest> boardOrders,
    QuerySnapshot<Map<String, dynamic>>? inventorySnapshot,
  }) async {
    final validOrders = boardOrders.where((o) => o.quantity > 0).toList();
    if (validOrders.isEmpty) {
      return const ProcurementPlan(lines: [], issues: []);
    }

    final inventory =
        inventorySnapshot ??
        await _db.collection(FirestoreCollections.inventory).get();
    final byId = {for (final doc in inventory.docs) doc.id: doc};

    final requiredByDocId = <String, int>{};
    final requiredByDocBoards = <String, Set<String>>{};

    final fallbackByKey = <String, _FallbackLine>{};
    final issueByKey = <String, _IssueAccum>{};

    void addIssue({
      required ProcurementIssueType type,
      required String label,
      required int qty,
      required String boardName,
    }) {
      final k = '${type.name}|${label.toLowerCase()}';
      final item = issueByKey.putIfAbsent(
        k,
        () => _IssueAccum(type: type, label: label),
      );
      item.requiredQty += qty;
      item.boards.add(boardName);
    }

    void addFallbackLine({
      required Map<String, dynamic> attrs,
      required String boardName,
      required int qty,
      required String label,
    }) {
      final rawPartNumber =
          attrs[FirestoreFields.partNumber]?.toString().trim() ?? '';
      final canonical = PartNormalizer.canonicalPartNumber(rawPartNumber);
      final key =
          canonical.isNotEmpty ? canonical : 'label:${label.toLowerCase()}';
      final partType = attrs['part_type']?.toString().trim() ?? '';
      final value = attrs[FirestoreFields.value]?.toString().trim() ?? '';
      final pkg = attrs['size']?.toString().trim() ?? '';
      final description = _describeFallback(
        rawPartNumber,
        partType,
        value,
        pkg,
      );
      final item = fallbackByKey.putIfAbsent(
        key,
        () => _FallbackLine(
          partNumber: rawPartNumber,
          partType: partType,
          package: pkg,
          description: description,
        ),
      );
      item.requiredQty += qty;
      item.boards.add(boardName);
    }

    for (final order in validOrders) {
      final boardName = order.board.name;
      final activeLines = order.board.bom.where((line) => !line.ignored);
      for (final line in activeLines) {
        final attrs = line.requiredAttributes;
        final requiredQty = line.qty * order.quantity;

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: attrs,
          inventorySnapshot: inventory,
        );

        if (matches.isEmpty) {
          final label = InventoryMatcher.makePartLabel(attrs);
          addIssue(
            type: ProcurementIssueType.unresolved,
            label: label,
            qty: requiredQty,
            boardName: boardName,
          );
          addFallbackLine(
            attrs: attrs,
            boardName: boardName,
            qty: requiredQty,
            label: label,
          );
          continue;
        }

        QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
        if (matches.length == 1) {
          chosen = matches.first;
        } else {
          final selectedRef = line.selectedComponentRef;
          if (selectedRef != null && selectedRef.isNotEmpty) {
            final exact = matches.where((m) => m.id == selectedRef).toList();
            if (exact.length == 1) {
              chosen = exact.first;
            }
          }
          if (chosen == null) {
            addIssue(
              type: ProcurementIssueType.ambiguous,
              label: InventoryMatcher.makePartLabel(attrs),
              qty: requiredQty,
              boardName: boardName,
            );
            continue;
          }
        }

        requiredByDocId[chosen.id] =
            (requiredByDocId[chosen.id] ?? 0) + requiredQty;
        requiredByDocBoards
            .putIfAbsent(chosen.id, () => <String>{})
            .add(boardName);
      }
    }

    final lines = <ProcurementLine>[];

    for (final entry in requiredByDocId.entries) {
      final doc = byId[entry.key];
      if (doc == null) continue;
      final data = doc.data();
      final requiredQty = entry.value;
      final inStock = (data[FirestoreFields.qty] as num?)?.toInt() ?? 0;
      final shortage = max(0, requiredQty - inStock);
      final partNumber =
          (data[FirestoreFields.partNumber]?.toString() ?? '').trim();
      final vendorLink = _cleanString(data[FirestoreFields.vendorLink]);
      lines.add(
        ProcurementLine(
          source: ProcurementLineSource.inventory,
          inventoryDocId: doc.id,
          partNumber: partNumber,
          digikeyPartNumber: extractDigiKeyPartNumber(
            vendorLink,
            fallbackPartNumber: partNumber,
          ),
          partType: _cleanString(data[FirestoreFields.type]),
          package: _cleanString(data[FirestoreFields.package]),
          description: _cleanString(data[FirestoreFields.description]),
          requiredQty: requiredQty,
          inStockQty: inStock,
          shortageQty: shortage,
          unitPrice: (data[FirestoreFields.pricePerUnit] as num?)?.toDouble(),
          vendorLink: vendorLink,
          boardNames:
              (requiredByDocBoards[entry.key] ?? <String>{}).toList()..sort(),
        ),
      );
    }

    for (final item in fallbackByKey.values) {
      lines.add(
        ProcurementLine(
          source: ProcurementLineSource.bomFallback,
          inventoryDocId: null,
          partNumber: item.partNumber,
          digikeyPartNumber: extractDigiKeyPartNumber(
            null,
            fallbackPartNumber: item.partNumber,
          ),
          partType: item.partType,
          package: item.package,
          description: item.description,
          requiredQty: item.requiredQty,
          inStockQty: 0,
          shortageQty: item.requiredQty,
          unitPrice: null,
          vendorLink: null,
          boardNames: item.boards.toList()..sort(),
        ),
      );
    }

    lines.sort((a, b) {
      final shortageCmp = b.shortageQty.compareTo(a.shortageQty);
      if (shortageCmp != 0) return shortageCmp;
      final typeCmp = a.source.index.compareTo(b.source.index);
      if (typeCmp != 0) return typeCmp;
      return a.partNumber.toLowerCase().compareTo(b.partNumber.toLowerCase());
    });

    final issues =
        issueByKey.values
            .map(
              (item) => ProcurementIssue(
                type: item.type,
                partLabel: item.label,
                requiredQty: item.requiredQty,
                boardNames: item.boards.toList()..sort(),
              ),
            )
            .toList()
          ..sort((a, b) {
            final qtyCmp = b.requiredQty.compareTo(a.requiredQty);
            if (qtyCmp != 0) return qtyCmp;
            return a.partLabel.toLowerCase().compareTo(
              b.partLabel.toLowerCase(),
            );
          });

    return ProcurementPlan(lines: lines, issues: issues);
  }

  static ProcurementPlan mergeManualLines(
    ProcurementPlan base,
    List<ManualProcurementLine> manualLines,
  ) {
    if (manualLines.isEmpty) return base;

    final lines = List<ProcurementLine>.from(base.lines);
    for (final item in manualLines) {
      if (item.quantity <= 0) continue;
      final partNumber = item.partNumber.trim();
      final description = item.description.trim();
      lines.add(
        ProcurementLine(
          source: ProcurementLineSource.manual,
          inventoryDocId: null,
          partNumber: partNumber,
          digikeyPartNumber: extractDigiKeyPartNumber(
            item.vendorLink,
            fallbackPartNumber: item.digikeyPartNumber ?? partNumber,
          ),
          partType: (item.partType ?? '').trim(),
          package: (item.package ?? '').trim(),
          description: description.isNotEmpty ? description : partNumber,
          requiredQty: item.quantity,
          inStockQty: 0,
          shortageQty: item.quantity,
          unitPrice: null,
          vendorLink: item.vendorLink?.trim(),
          boardNames: [item.boardLabel],
        ),
      );
    }

    lines.sort((a, b) {
      final shortageCmp = b.shortageQty.compareTo(a.shortageQty);
      if (shortageCmp != 0) return shortageCmp;
      final typeCmp = a.source.index.compareTo(b.source.index);
      if (typeCmp != 0) return typeCmp;
      return a.partNumber.toLowerCase().compareTo(b.partNumber.toLowerCase());
    });

    return ProcurementPlan(lines: lines, issues: base.issues);
  }

  static String? extractDigiKeyPartNumber(
    String? vendorLink, {
    String? fallbackPartNumber,
  }) {
    final fallback = _normalizedDigiKeyPn(fallbackPartNumber);
    if (vendorLink == null || vendorLink.trim().isEmpty) {
      return fallback;
    }

    final uri = Uri.tryParse(vendorLink.trim());
    if (uri == null) return fallback;

    final host = uri.host.toLowerCase();
    if (!host.contains('digikey')) return fallback;

    for (final segment in uri.pathSegments.reversed) {
      final value = _normalizedDigiKeyPn(segment);
      if (value != null) return value;
    }

    for (final key in ['item', 'part', 'partnumber', 'pn']) {
      final value = _normalizedDigiKeyPn(uri.queryParameters[key]);
      if (value != null) return value;
    }

    return fallback;
  }

  static String? _normalizedDigiKeyPn(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9./-]+-ND$', caseSensitive: false).hasMatch(value)) {
      return value.toUpperCase();
    }
    return null;
  }

  static String _describeFallback(
    String rawPartNumber,
    String partType,
    String value,
    String package,
  ) {
    if (rawPartNumber.isNotEmpty) return rawPartNumber;
    final parts = <String>[];
    if (partType.isNotEmpty) parts.add(partType);
    if (value.isNotEmpty) parts.add(value);
    if (package.isNotEmpty) parts.add(package);
    return parts.isEmpty ? 'Unmapped BOM part' : parts.join(' ');
  }

  static String _cleanString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }
}

class _IssueAccum {
  final ProcurementIssueType type;
  final String label;
  int requiredQty = 0;
  final Set<String> boards = <String>{};

  _IssueAccum({required this.type, required this.label});
}

class _FallbackLine {
  final String partNumber;
  final String partType;
  final String package;
  final String description;
  int requiredQty = 0;
  final Set<String> boards = <String>{};

  _FallbackLine({
    required this.partNumber,
    required this.partType,
    required this.package,
    required this.description,
  });
}

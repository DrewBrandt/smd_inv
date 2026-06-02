import 'package:csv/csv.dart';

import 'board.dart';

const Object _unsetProcurementValue = Object();

enum ProcurementIssueType { unresolved, ambiguous }

class BoardOrderRequest {
  final BoardDoc board;
  final int quantity;

  const BoardOrderRequest({required this.board, required this.quantity});
}

class ProcurementIssue {
  final ProcurementIssueType type;
  final String partLabel;
  final int requiredQty;
  final List<String> boardNames;

  const ProcurementIssue({
    required this.type,
    required this.partLabel,
    required this.requiredQty,
    required this.boardNames,
  });

  String get typeLabel {
    switch (type) {
      case ProcurementIssueType.unresolved:
        return 'Unresolved';
      case ProcurementIssueType.ambiguous:
        return 'Ambiguous';
    }
  }
}

enum ProcurementLineSource { inventory, bomFallback, manual }

class ManualProcurementLine {
  final String partNumber;
  final String? digikeyPartNumber;
  final String description;
  final int quantity;
  final String? vendorLink;
  final String? partType;
  final String? package;
  final String boardLabel;

  const ManualProcurementLine({
    required this.partNumber,
    required this.digikeyPartNumber,
    required this.description,
    required this.quantity,
    this.vendorLink,
    this.partType,
    this.package,
    this.boardLabel = 'Manual',
  });
}

class ProcurementLine {
  final ProcurementLineSource source;
  final String? inventoryDocId;
  final String partNumber;
  final String? digikeyPartNumber;
  final String partType;
  final String value;
  final String package;
  final String description;
  final int requiredQty;
  final int inStockQty;
  final int shortageQty;
  final int purchaseQty;
  final int? lowStockThreshold;
  final double? unitPrice;
  final String? vendorLink;
  final List<String> boardNames;

  const ProcurementLine({
    required this.source,
    required this.inventoryDocId,
    required this.partNumber,
    required this.digikeyPartNumber,
    required this.partType,
    this.value = '',
    required this.package,
    required this.description,
    required this.requiredQty,
    required this.inStockQty,
    required this.shortageQty,
    int? purchaseQty,
    this.lowStockThreshold,
    required this.unitPrice,
    required this.vendorLink,
    required this.boardNames,
  }) : purchaseQty = purchaseQty ?? shortageQty;

  bool get needsOrder => purchaseQty > 0;

  int get remainingAfterRequired => inStockQty - requiredQty;

  bool get isLowStock =>
      !needsOrder &&
      source == ProcurementLineSource.inventory &&
      shortageQty == 0 &&
      lowStockThreshold != null &&
      remainingAfterRequired < lowStockThreshold!;

  bool get hasDigiKeyPartNumber =>
      (digikeyPartNumber?.trim().isNotEmpty ?? false);

  bool get hasOrderIdentifier {
    final id = preferredOrderIdentifier;
    return id.isNotEmpty;
  }

  String get preferredOrderIdentifier {
    final dk = digikeyPartNumber?.trim() ?? '';
    if (dk.isNotEmpty) return dk;
    return partNumber.trim();
  }

  double? get shortageExtendedCost {
    if (unitPrice == null || purchaseQty <= 0) return null;
    return unitPrice! * purchaseQty;
  }

  ProcurementLine copyWith({
    Object? digikeyPartNumber = _unsetProcurementValue,
    int? purchaseQty,
  }) {
    return ProcurementLine(
      source: source,
      inventoryDocId: inventoryDocId,
      partNumber: partNumber,
      digikeyPartNumber:
          identical(digikeyPartNumber, _unsetProcurementValue)
              ? this.digikeyPartNumber
              : digikeyPartNumber as String?,
      partType: partType,
      value: value,
      package: package,
      description: description,
      requiredQty: requiredQty,
      inStockQty: inStockQty,
      shortageQty: shortageQty,
      purchaseQty: purchaseQty ?? this.purchaseQty,
      lowStockThreshold: lowStockThreshold,
      unitPrice: unitPrice,
      vendorLink: vendorLink,
      boardNames: boardNames,
    );
  }
}

class ProcurementPlan {
  final List<ProcurementLine> lines;
  final List<ProcurementIssue> issues;

  const ProcurementPlan({required this.lines, required this.issues});

  List<ProcurementLine> get orderableLines =>
      lines.where((l) => l.needsOrder).toList(growable: false);

  List<ProcurementLine> get lowStockLines =>
      lines.where((l) => l.isLowStock).toList(growable: false);

  List<ProcurementLine> get exportableLines =>
      orderableLines.where((l) => l.hasOrderIdentifier).toList(growable: false);

  int get totalRequiredQty =>
      lines.fold(0, (sum, line) => sum + line.requiredQty);

  int get totalShortageQty =>
      lines.fold(0, (sum, line) => sum + line.purchaseQty);

  int get unresolvedCount =>
      issues.where((i) => i.type == ProcurementIssueType.unresolved).length;

  int get ambiguousCount =>
      issues.where((i) => i.type == ProcurementIssueType.ambiguous).length;

  double get knownOrderCost => orderableLines.fold<double>(0.0, (sum, line) {
    final ext = line.shortageExtendedCost;
    return ext == null ? sum : sum + ext;
  });

  String toDigiKeyCsv() {
    final rows = <List<dynamic>>[
      [
        'DigiKey Part Number',
        'Manufacturer Part Number',
        'Quantity',
        'Customer Reference',
        'Description',
        'Vendor Link',
      ],
    ];

    for (final line in exportableLines) {
      rows.add([
        line.digikeyPartNumber ?? '',
        line.partNumber,
        line.purchaseQty,
        line.boardNames.join('; '),
        line.description,
        line.vendorLink ?? '',
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  String toQuickOrderText() {
    final buffer = StringBuffer();
    for (final line in exportableLines) {
      buffer.writeln('${line.preferredOrderIdentifier},${line.purchaseQty}');
    }
    return buffer.toString().trimRight();
  }
}

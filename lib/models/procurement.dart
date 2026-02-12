import 'package:csv/csv.dart';

import 'board.dart';

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
  final String package;
  final String description;
  final int requiredQty;
  final int inStockQty;
  final int shortageQty;
  final double? unitPrice;
  final String? vendorLink;
  final List<String> boardNames;

  const ProcurementLine({
    required this.source,
    required this.inventoryDocId,
    required this.partNumber,
    required this.digikeyPartNumber,
    required this.partType,
    required this.package,
    required this.description,
    required this.requiredQty,
    required this.inStockQty,
    required this.shortageQty,
    required this.unitPrice,
    required this.vendorLink,
    required this.boardNames,
  });

  bool get needsOrder => shortageQty > 0;

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
    if (unitPrice == null || shortageQty <= 0) return null;
    return unitPrice! * shortageQty;
  }
}

class ProcurementPlan {
  final List<ProcurementLine> lines;
  final List<ProcurementIssue> issues;

  const ProcurementPlan({required this.lines, required this.issues});

  List<ProcurementLine> get orderableLines =>
      lines.where((l) => l.needsOrder).toList(growable: false);

  List<ProcurementLine> get exportableLines =>
      orderableLines.where((l) => l.hasOrderIdentifier).toList(growable: false);

  int get totalRequiredQty =>
      lines.fold(0, (sum, line) => sum + line.requiredQty);

  int get totalShortageQty =>
      lines.fold(0, (sum, line) => sum + line.shortageQty);

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
        line.shortageQty,
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
      buffer.writeln('${line.preferredOrderIdentifier},${line.shortageQty}');
    }
    return buffer.toString().trimRight();
  }
}

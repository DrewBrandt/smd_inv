// lib/models/readiness.dart
class Readiness {
  final int buildableQty;
  final double readyPct; // 0.0 to 1.0
  final List<Shortfall> shortfalls;

  /// Parts that are in stock in sufficient quantity but match more than one
  /// inventory entry (e.g. the same part split across multiple locations).
  /// The board is still buildable for these — a location just has to be picked
  /// at build time. Kept separate from [shortfalls] so the UI can distinguish
  /// "not buildable, part missing" from "buildable, choose where to pull from".
  final List<String> ambiguousParts;
  final double? totalCost;

  const Readiness({
    required this.buildableQty,
    required this.readyPct,
    required this.shortfalls,
    this.ambiguousParts = const [],
    this.totalCost,
  });
}

class Shortfall {
  final String part;
  final int qty;

  const Shortfall(this.part, this.qty);
}

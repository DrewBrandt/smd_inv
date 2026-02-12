// lib/models/readiness.dart
class Readiness {
  final int buildableQty;
  final double readyPct; // 0.0 to 1.0
  final List<Shortfall> shortfalls;
  final double? totalCost;

  const Readiness({
    required this.buildableQty,
    required this.readyPct,
    required this.shortfalls,
    this.totalCost,
  });
}

class Shortfall {
  final String part;
  final int qty;

  const Shortfall(this.part, this.qty);
}

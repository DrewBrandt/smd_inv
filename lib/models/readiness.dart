class Shortfall {
  final String label; // e.g., "10k 0402" or "ESP32"
  final int missing; // how many we’re short for one unit
  const Shortfall(this.label, this.missing);
}

class Readiness {
  final int buildableQty; // 0, 1, 2...
  final double readyPct; // 0.0..1.0
  final List<Shortfall> shortfalls;
  const Readiness({required this.buildableQty, required this.readyPct, required this.shortfalls});
}

class PartNormalizer {
  static String normalizePartType(String raw) {
    final type = raw.trim().toLowerCase();
    if (type == 'cap' || type == 'c') return 'capacitor';
    if (type == 'res' || type == 'r') return 'resistor';
    if (type == 'ind' || type == 'l') return 'inductor';
    if (type == 'conn' || type == 'con') return 'connector';
    if (type == 'u') return 'ic';
    return type;
  }

  static bool isPassive(String partType) {
    final type = normalizePartType(partType);
    return type == 'capacitor' ||
        type == 'resistor' ||
        type == 'inductor' ||
        type == 'diode' ||
        type == 'led';
  }

  static String normalizePackage(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    const metricToImperial = {
      '1005': '0402',
      '1608': '0603',
      '2012': '0805',
      '3216': '1206',
      '3225': '1210',
      '2520': '1008',
    };
    return metricToImperial[s] ?? s;
  }

  static String canonicalPackage(String raw) {
    return canonicalPartNumber(normalizePackage(raw));
  }

  static String normalizeValue(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return s;

    s = s.replaceAll('µ', 'u').replaceAll(RegExp(r'\s+'), '');
    s = s.replaceAllMapped(RegExp(r'([unpkm])f$'), (m) => m.group(1)!);

    // Keep resistor notation like 4k7/5k1 as-is for better human alignment.
    final resistorEmbed = RegExp(r'^\d+k\d+$').hasMatch(s);
    if (resistorEmbed) return s;

    final embed = RegExp(r'^(\d+)([unpkmg])(\d+)$').firstMatch(s);
    if (embed != null) {
      final intPart = embed.group(1)!;
      final unit = embed.group(2)!;
      final frac = embed.group(3)!;
      if (RegExp(r'^0+$').hasMatch(frac)) return '$intPart$unit';
      return '$intPart.$frac$unit';
    }

    return s;
  }

  static bool valuesLikelyEqual({
    required String a,
    required String b,
    required String partType,
  }) {
    final na = normalizeValue(a);
    final nb = normalizeValue(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;

    final type = normalizePartType(partType);
    final aBase = _toBaseValue(na, type);
    final bBase = _toBaseValue(nb, type);
    if (aBase == null || bBase == null) return false;

    final delta = (aBase - bBase).abs();
    final norm = aBase.abs() > bBase.abs() ? aBase.abs() : bBase.abs();
    if (norm == 0) return delta == 0;
    return (delta / norm) < 0.000001;
  }

  static double? _toBaseValue(String normalizedValue, String partType) {
    if (partType == 'resistor') {
      return _parseWithUnit(
        normalizedValue,
        unitMultipliers: const {
          'r': 1.0,
          'k': 1000.0,
          'm': 1000000.0,
          'g': 1000000000.0,
        },
      );
    }
    if (partType == 'capacitor' || partType == 'inductor') {
      return _parseWithUnit(
        normalizedValue,
        unitMultipliers: const {'p': 1e-12, 'n': 1e-9, 'u': 1e-6, 'm': 1e-3},
      );
    }
    return null;
  }

  static double? _parseWithUnit(
    String value, {
    required Map<String, double> unitMultipliers,
  }) {
    final simple = RegExp(r'^(\d+(?:\.\d+)?)([a-z])?$').firstMatch(value);
    if (simple != null) {
      final n = double.tryParse(simple.group(1)!);
      if (n == null) return null;
      final unit = simple.group(2);
      if (unit == null) return n;
      final mul = unitMultipliers[unit];
      if (mul == null) return null;
      return n * mul;
    }

    final embedded = RegExp(r'^(\d+)([a-z])(\d+)$').firstMatch(value);
    if (embedded != null) {
      final whole = embedded.group(1)!;
      final unit = embedded.group(2)!;
      final frac = embedded.group(3)!;
      final mul = unitMultipliers[unit];
      if (mul == null) return null;
      final asDouble = double.tryParse('$whole.$frac');
      if (asDouble == null) return null;
      return asDouble * mul;
    }
    return null;
  }

  static String canonicalPartNumber(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String canonicalText(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

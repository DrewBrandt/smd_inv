import 'package:flutter/material.dart';

const Map<String, Color> kBoardCategoryColors = {
  'Radio': Color(0xFF77C0FC),
  'FC': Color(0xFF88E08B),
  'GS': Color(0xFFFFA513),
  'Misc': Colors.grey,
};

Color boardCategoryColor(String? key, Color fallback) {
  if (key == null) return fallback;
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty) return fallback;

  for (final entry in kBoardCategoryColors.entries) {
    if (entry.key.toLowerCase() == normalized) {
      return entry.value;
    }
  }

  return fallback;
}

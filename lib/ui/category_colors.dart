import 'package:flutter/material.dart';

const Map<String, Color> kCategoryColors = {
  'Radio': Color(0xFF77C0FC),
  'FC': Color(0xFF88E08B),
  'GS': Color.fromARGB(255, 255, 165, 19),
  'Misc': Colors.grey,

};

Color categoryColor(String? key, Color fallback) {
  if (key == null) return fallback;
  return kCategoryColors[key] ?? fallback;
}

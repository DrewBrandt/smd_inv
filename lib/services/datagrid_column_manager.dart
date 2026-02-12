import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages column widths for data grids with persistence and dynamic resizing
class DataGridColumnManager {
  final String persistKey;
  final List<GridColumnConfig> columns;

  Map<String, double> _userWidths = {};
  bool _isResizing = false;

  DataGridColumnManager({required this.persistKey, required this.columns});

  /// Load saved column widths from SharedPreferences
  Future<void> loadSavedWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('dg_widths:$persistKey');
    if (json != null) {
      try {
        final map = jsonDecode(json);
        _userWidths = Map<String, double>.from(map);
      } catch (e) {
        debugPrint('Failed to load column widths: $e');
        _userWidths = {};
      }
    }
  }

  /// Save current column widths to SharedPreferences
  Future<void> saveWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dg_widths:$persistKey', jsonEncode(_userWidths));
    } catch (e) {
      debugPrint('Failed to save column widths: $e');
    }
  }

  /// Get minimum width for a column based on field name
  double getMinWidth(String field) {
    final f = field.toLowerCase();
    if (f == '_ignored') return 60;
    if (f == 'qty' || f == 'quantity' || f == 'count') return 84;
    if (f == 'notes' || f == 'description' || f == 'desc') return 320;
    if (f == 'datasheet' || f == 'url' || f == 'link' || f == 'vendor_link') {
      return 220;
    }
    if (f == 'part_#' || f.endsWith('_id')) return 180;
    if (f == 'size' || f == 'value' || f == 'package') return 120;
    if (f == 'location') return 160;
    if (f == 'type' || f == 'category' || f == 'parttype' || f == 'part_type') {
      return 120;
    }
    return 140;
  }

  /// Get expansion weight for a column (higher = grows more when extra space available)
  double getWeight(GridColumnConfig column) {
    final f = column.field.toLowerCase();
    if (f == 'notes' || f == 'description' || f == 'desc') return 3.0;
    if (f == 'part_#') return 2.0;
    if (f == 'datasheet' || f == 'url' || f == 'link' || f == 'vendor_link') {
      return 0; // Don't grow
    }
    return 1.0;
  }

  /// Calculate column widths based on constraints and saved preferences
  Map<String, double> calculateWidths(BoxConstraints constraints) {
    // Start with minimum widths
    final mins = <String, double>{
      for (final c in columns) c.field: getMinWidth(c.field),
    };
    final weights = <String, double>{
      for (final c in columns) c.field: getWeight(c),
    };
    final widths = <String, double>{
      for (final c in columns) c.field: mins[c.field]!,
    };

    // Apply user-saved widths (but respect minimums)
    for (final e in _userWidths.entries) {
      if (widths.containsKey(e.key)) {
        widths[e.key] = e.value < mins[e.key]! ? mins[e.key]! : e.value;
      }
    }

    // Distribute extra space proportionally by weight (only when not resizing)
    if (constraints.maxWidth.isFinite && !_isResizing) {
      final maxW = constraints.maxWidth;
      final sumNow = widths.values.fold<double>(0, (a, b) => a + b);
      final extra = maxW - sumNow;

      if (extra > 0) {
        // Find columns that can grow (not manually resized, weight > 0)
        final growable =
            columns
                .where(
                  (c) =>
                      !_userWidths.containsKey(c.field) &&
                      (weights[c.field] ?? 0) > 0,
                )
                .toList();

        final totalWeight = growable.fold<double>(
          0.0,
          (a, c) => a + (weights[c.field] ?? 0),
        );

        if (totalWeight > 0) {
          // Distribute proportionally by weight
          for (final c in growable) {
            final w = weights[c.field] ?? 0;
            widths[c.field] = widths[c.field]! + extra * (w / totalWeight);
          }
        } else {
          // No growable columns, give extra space to last column
          widths[columns.last.field] = widths[columns.last.field]! + extra;
        }
      }
    }

    return widths;
  }

  /// Call when column resize starts
  void onColumnResizeStart() {
    _isResizing = true;
  }

  /// Call when column resize updates
  void onColumnResizeUpdate(String field, double newWidth) {
    _userWidths[field] = newWidth;
  }

  /// Call when column resize ends
  Future<void> onColumnResizeEnd() async {
    _isResizing = false;
    await saveWidths();
  }

  /// Clear all saved widths
  Future<void> clearSavedWidths() async {
    _userWidths.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dg_widths:$persistKey');
    } catch (e) {
      debugPrint('Failed to clear column widths: $e');
    }
  }
}

/// Configuration for a grid column
class GridColumnConfig {
  final String field;
  final String label;
  final double? width;
  final double? minWidth;

  const GridColumnConfig({
    required this.field,
    required this.label,
    this.width,
    this.minWidth,
  });
}

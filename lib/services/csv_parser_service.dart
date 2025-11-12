import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

/// Service for parsing CSV/TSV files with header detection
class CsvParserService {
  /// Parse CSV/TSV text into structured data
  ///
  /// [text] - Raw CSV/TSV text
  /// [expectedColumns] - Column names to look for in header (case-insensitive fuzzy match)
  /// [autoDetectDelimiter] - If true, automatically detect tab vs comma
  static CsvParseResult parse(
    String text, {
    required List<String> expectedColumns,
    bool autoDetectDelimiter = true,
  }) {
    if (text.trim().isEmpty) {
      return CsvParseResult.error('Empty input');
    }

    // Auto-detect delimiter (tab vs comma)
    String delimiter = ',';
    if (autoDetectDelimiter) {
      final lines = text.split('\n');
      if (lines.isNotEmpty) {
        final firstLine = lines.first;
        final commaCount = ','.allMatches(firstLine).length;
        final tabCount = '\t'.allMatches(firstLine).length;
        if (tabCount > commaCount) {
          delimiter = '\t';
        }
      }
    }

    // Parse CSV
    final converter = CsvToListConverter(
      eol: '\n',
      fieldDelimiter: delimiter,
      shouldParseNumbers: false,
    );

    List<List<dynamic>> rows;
    try {
      rows = converter.convert(text);
    } catch (e) {
      return CsvParseResult.error('Failed to parse: $e');
    }

    if (rows.isEmpty) {
      return CsvParseResult.error('No rows found');
    }

    // Check if first row is header
    final firstRowStrings = rows.first
      .map((e) => e.toString().trim().toLowerCase())
      .toList();

    final isHeader = _hasHeaderRow(firstRowStrings, expectedColumns);

    final headerRow = isHeader ? firstRowStrings : <String>[];
    final dataRows = isHeader ? rows.skip(1).toList() : rows;

    // Map headers to expected columns (fuzzy matching)
    final columnMap = _buildColumnMap(headerRow, expectedColumns);

    return CsvParseResult.success(
      headers: headerRow,
      dataRows: dataRows,
      columnMap: columnMap,
      delimiter: delimiter,
    );
  }

  /// Parse CSV/TSV from file picker
  static Future<CsvParseResult> parseFromFile({
    required List<String> expectedColumns,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'tsv', 'txt'],
    );

    if (result == null || result.files.isEmpty) {
      return CsvParseResult.error('No file selected');
    }

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      return CsvParseResult.error('Failed to read file');
    }

    String text;
    try {
      text = utf8.decode(bytes);
    } catch (e) {
      return CsvParseResult.error('Failed to decode file: $e');
    }

    return parse(text, expectedColumns: expectedColumns);
  }

  /// Check if first row looks like a header
  static bool _hasHeaderRow(List<String> firstRow, List<String> expectedColumns) {
    // If any expected column is found in first row, assume it's a header
    for (final expected in expectedColumns) {
      final exp = expected.toLowerCase();
      for (final cell in firstRow) {
        if (cell.contains(exp) || exp.contains(cell)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Build mapping from expected column names to column indices
  static Map<String, int> _buildColumnMap(
    List<String> headers,
    List<String> expectedColumns,
  ) {
    final columnMap = <String, int>{};

    for (final expected in expectedColumns) {
      final exp = expected.toLowerCase();

      // Find best matching header (headers are already lowercase)
      for (int i = 0; i < headers.length; i++) {
        final header = headers[i];

        // Exact match
        if (header == exp) {
          columnMap[expected] = i;
          break;
        }

        // Contains match (either direction)
        // Note: Both header and exp are already lowercase
        if (header.contains(exp) || exp.contains(header)) {
          columnMap[expected] = i;
          break;
        }
      }
    }

    return columnMap;
  }
}

/// Result of CSV parsing operation
class CsvParseResult {
  final bool success;
  final String? error;
  final List<String> headers;
  final List<List<dynamic>> dataRows;
  final Map<String, int> columnMap;
  final String delimiter;

  CsvParseResult._({
    required this.success,
    this.error,
    this.headers = const [],
    this.dataRows = const [],
    this.columnMap = const {},
    this.delimiter = ',',
  });

  factory CsvParseResult.success({
    required List<String> headers,
    required List<List<dynamic>> dataRows,
    required Map<String, int> columnMap,
    required String delimiter,
  }) {
    return CsvParseResult._(
      success: true,
      headers: headers,
      dataRows: dataRows,
      columnMap: columnMap,
      delimiter: delimiter,
    );
  }

  factory CsvParseResult.error(String message) {
    return CsvParseResult._(success: false, error: message);
  }

  /// Get cell value by column name with fallback
  String getCellValue(
    List<dynamic> row,
    String columnName, {
    String defaultValue = '',
  }) {
    final index = columnMap[columnName];
    if (index == null || index >= row.length) return defaultValue;
    return row[index]?.toString().trim() ?? defaultValue;
  }

  /// Check if column exists in parsed data
  bool hasColumn(String columnName) => columnMap.containsKey(columnName);

  /// Get all values for a column
  List<String> getColumnValues(String columnName) {
    if (!hasColumn(columnName)) return [];
    return dataRows.map((row) => getCellValue(row, columnName)).toList();
  }
}

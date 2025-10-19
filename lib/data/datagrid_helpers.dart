// lib/data/datagrid_helpers.dart
// (These are your functions from ListMapDataSource, now in a shared file)

dynamic getNestedMapValue(Map<String, dynamic> map, String path) {
  if (!path.contains('.')) {
    return map[path];
  }
  final parts = path.split('.');
  dynamic current = map;
  for (var i = 0; i < parts.length; i++) {
    if (current == null || !(current is Map)) return null;
    current = current[parts[i]];
  }
  return current;
}

void setNestedMapValue(Map<String, dynamic> map, String path, dynamic value) {
  if (!path.contains('.')) {
    map[path] = value;
    return;
  }
  final parts = path.split('.');
  dynamic current = map;
  for (var i = 0; i < parts.length - 1; i++) {
    // Go to the parent map
    final key = parts[i];
    if (current[key] == null || !(current[key] is Map)) {
      current[key] = <String, dynamic>{}; // Create nested map if it doesn't exist
    }
    current = current[key];
  }
  current[parts.last] = value; // Set the final value
}

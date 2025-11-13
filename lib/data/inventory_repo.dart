import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Repository for inventory operations with centralized stream and filtering logic
class InventoryRepo {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection(FirestoreCollections.inventory);

  /// Stream all inventory items with optional type filtering
  /// Type filtering is applied at the query level for better performance
  Stream<List<Doc>> streamAll({List<String>? typeFilter}) {
    Query<Map<String, dynamic>> query = _col;

    // Apply type filter if provided
    if (typeFilter != null && typeFilter.isNotEmpty) {
      query = query.where('type', whereIn: typeFilter);
    }

    // Simple ordering (no index needed)
    query = query.orderBy('type');

    return query.snapshots().map((snap) => snap.docs);
  }

  /// Stream inventory with client-side filtering for multiple dimensions
  /// Use this when you need to filter by multiple fields (type, package, location)
  Stream<List<Doc>> streamFiltered({
    List<String>? typeFilter,
    List<String>? packageFilter,
    List<String>? locationFilter,
  }) {
    // Get all items (or type-filtered if specified)
    return streamAll(typeFilter: typeFilter).map((docs) {
      var filtered = docs;

      // Apply package filter
      if (packageFilter != null && packageFilter.isNotEmpty) {
        filtered = filtered.where((d) {
          final pkg = d.data()['package']?.toString() ?? '';
          return packageFilter.contains(pkg);
        }).toList();
      }

      // Apply location filter
      if (locationFilter != null && locationFilter.isNotEmpty) {
        filtered = filtered.where((d) {
          final loc = d.data()['location']?.toString() ?? '';
          return locationFilter.contains(loc);
        }).toList();
      }

      return filtered;
    });
  }

  /// Generic collection stream for any Firestore collection
  /// Useful for simple collection streaming without filters
  Stream<List<Doc>> streamCollection(String collectionName) {
    return _db.collection(collectionName).snapshots().map((snap) => snap.docs);
  }

  /// Update a specific field in an inventory document
  Future<void> updateField(String docId, String field, dynamic value) async {
    await _col.doc(docId).update({
      field: value,
      FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
    });
  }

  /// Delete an inventory document
  Future<void> delete(String docId) async {
    await _col.doc(docId).delete();
  }

  /// Get a single inventory document
  Future<DocumentSnapshot<Map<String, dynamic>>> getById(String docId) async {
    return await _col.doc(docId).get();
  }

  /// Create a new inventory item
  Future<String> create(Map<String, dynamic> data) async {
    data[FirestoreFields.createdAt] = FieldValue.serverTimestamp();
    data[FirestoreFields.lastUpdated] = FieldValue.serverTimestamp();

    final docRef = await _col.add(data);
    return docRef.id;
  }

  /// Increment/decrement quantity for an inventory item
  Future<void> adjustQuantity(String docId, int delta) async {
    await _col.doc(docId).update({
      FirestoreFields.qty: FieldValue.increment(delta),
      FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
    });
  }
}

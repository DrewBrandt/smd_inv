// lib/data/unified_firestore_streams.dart
import 'package:cloud_firestore/cloud_firestore.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Stream inventory with optional type filtering
Stream<List<Doc>> inventoryStream({List<String>? typeFilter}) {
  Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('inventory');

  // Apply type filter if provided
  if (typeFilter != null && typeFilter.isNotEmpty) {
    query = query.where('type', whereIn: typeFilter);
  }

  // Simple ordering (no index needed)
  query = query.orderBy('type');

  return query.snapshots().map((snap) => snap.docs);
}

/// Legacy: Keep for backwards compatibility if needed elsewhere
Stream<List<Doc>> collectionStream(String collection) {
  return FirebaseFirestore.instance.collection(collection).snapshots().map((snap) => snap.docs);
}

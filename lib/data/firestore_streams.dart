import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> collectionStream(String collection) {
  final col = FirebaseFirestore.instance
      .collection(collection)
      .withConverter<Map<String, dynamic>>(
        fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
        toFirestore: (m, _) => m,
      );

  // Use Firestore's real-time snapshots for ALL platforms.
  // The SDK handles this efficiently on desktop, mobile, and web.
  // This will only emit new data when a change actually happens.
  return col.snapshots().map((snap) => snap.docs);
}

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

bool get _isDesktop =>
    const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(defaultTargetPlatform);

Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> collectionStream(String collection) {
  final col = FirebaseFirestore.instance
      .collection(collection)
      .withConverter<Map<String, dynamic>>(
        fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
        toFirestore: (m, _) => m,
      );

  if (_isDesktop) {
    return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) => col.get()).map((snap) => snap.docs);
  } else {
    return col.snapshots().map((snap) => snap.docs);
  }
}

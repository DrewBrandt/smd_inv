// lib/models/board.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';

class BomLine {
  int qty;
  String? category;
  Map<String, dynamic> requiredAttributes;
  DocumentReference<Map<String, dynamic>>? selectedComponentRef;
  String? notes;

  BomLine({
    required this.qty,
    this.category,
    required this.requiredAttributes,
    this.selectedComponentRef,
    this.notes,
  });

  factory BomLine.fromMap(Map<String, dynamic> m, FirebaseFirestore db) {
    DocumentReference<Map<String, dynamic>>? ref;
    final rawRef = m[FirestoreFields.selectedComponentRef];
    if (rawRef is DocumentReference) {
      ref = rawRef.withConverter<Map<String, dynamic>>(
        fromFirestore: (s, _) => s.data() ?? {},
        toFirestore: (v, _) => v,
      );
    } else if (rawRef is String && rawRef.isNotEmpty) {
      // if stored as path string
      try {
        ref = db
            .doc(rawRef)
            .withConverter<Map<String, dynamic>>(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (v, _) => v,
            );
      } catch (e) {
        // invalid path string
      }
    }

    return BomLine(
      qty: (m[FirestoreFields.qty] ?? 0) as int,
      category: m[FirestoreFields.category] as String?,
      requiredAttributes: Map<String, dynamic>.from(
        m[FirestoreFields.requiredAttributes] ?? const {},
      ),
      selectedComponentRef: ref,
      notes: m[FirestoreFields.notes] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    FirestoreFields.qty: qty,
    if (category != null) FirestoreFields.category: category,
    FirestoreFields.requiredAttributes: requiredAttributes,
    FirestoreFields.selectedComponentRef: selectedComponentRef,
    if (notes != null) FirestoreFields.notes: notes,
  };
}

class BoardDoc {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String? color; // hex like #2D7FF9
  final String? imageUrl;
  final List<BomLine> bom;

  BoardDoc({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.color,
    this.imageUrl,
    required this.bom,
  });

  factory BoardDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? {};
    final db = snap.reference.firestore;
    final bomRaw = (m[FirestoreFields.bom] as List?) ?? const [];
    return BoardDoc(
      id: snap.id,
      name: (m[FirestoreFields.name] ?? 'Untitled') as String,
      description: m[FirestoreFields.description] as String?,
      category: m[FirestoreFields.category] as String?,
      color: m[FirestoreFields.color] as String?,
      imageUrl: m[FirestoreFields.imageUrl] as String?,
      bom:
          bomRaw
              .map(
                (e) => BomLine.fromMap(Map<String, dynamic>.from(e as Map), db),
              )
              .toList(),
    );
  }
}

// lib/models/board.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BomLine {
  int qty;
  String? category;
  Map<String, dynamic> requiredAttributes;
  DocumentReference<Map<String, dynamic>>? selectedComponentRef;
  String? notes;

  BomLine({required this.qty, this.category, required this.requiredAttributes, this.selectedComponentRef, this.notes});

  factory BomLine.fromMap(Map<String, dynamic> m, FirebaseFirestore db) {
    DocumentReference<Map<String, dynamic>>? ref;
    final rawRef = m['selected_component_ref'];
    if (rawRef is DocumentReference) {
      ref = rawRef.withConverter<Map<String, dynamic>>(
        fromFirestore: (s, _) => s.data() ?? {},
        toFirestore: (v, _) => v,
      );
    } else if (rawRef is String && rawRef.isNotEmpty) {
      // if stored as path string
      ref = db
          .doc(rawRef)
          .withConverter<Map<String, dynamic>>(fromFirestore: (s, _) => s.data() ?? {}, toFirestore: (v, _) => v);
    }

    return BomLine(
      qty: (m['qty'] ?? 0) as int,
      category: m['category'] as String?,
      requiredAttributes: Map<String, dynamic>.from(m['required_attributes'] ?? const {}),
      selectedComponentRef: ref,
      notes: m['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'qty': qty,
    if (category != null) 'category': category,
    'required_attributes': requiredAttributes,
    'selected_component_ref': selectedComponentRef,
    if (notes != null) 'notes': notes,
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
    final bomRaw = (m['bom'] as List?) ?? const [];
    return BoardDoc(
      id: snap.id,
      name: (m['name'] ?? 'Untitled') as String,
      description: m['description'] as String?,
      category: m['category'] as String?,
      color: m['color'] as String?,
      imageUrl: m['image'] as String?,
      bom: bomRaw.map((e) => BomLine.fromMap(Map<String, dynamic>.from(e as Map), db)).toList(),
    );
  }
}

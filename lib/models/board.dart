// lib/models/board.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/firestore_constants.dart';

class BomLine {
  String designators;
  int qty;
  String? category;
  String? description;
  Map<String, dynamic> requiredAttributes;
  String? notes;
  bool ignored;

  BomLine({
    required this.designators,
    required this.qty,
    this.category,
    this.description,
    required this.requiredAttributes,
    this.notes,
    this.ignored = false,
  });

  factory BomLine.fromMap(Map<String, dynamic> m) {
    final required = Map<String, dynamic>.from(
      m[FirestoreFields.requiredAttributes] ?? const {},
    );

    return BomLine(
      designators: m['designators'] as String? ?? '?',
      qty: _toInt(m[FirestoreFields.qty]),
      category: m[FirestoreFields.category] as String?,
      description: m['description'] as String?,
      requiredAttributes: required,
      notes: m[FirestoreFields.notes] as String?,
      ignored: m['_ignored'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'designators': designators,
    FirestoreFields.qty: qty,
    if (category != null) FirestoreFields.category: category,
    if (description != null && description!.isNotEmpty)
      'description': description,
    FirestoreFields.requiredAttributes: requiredAttributes,
    if (notes != null) FirestoreFields.notes: notes,
    '_ignored': ignored,
  };

  String? get selectedComponentRef {
    final raw = requiredAttributes[FirestoreFields.selectedComponentRef];
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int _toInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
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
              .map((e) => BomLine.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList(),
    );
  }
}

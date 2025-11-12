/// Firestore collection names used throughout the app
abstract class FirestoreCollections {
  static const String inventory = 'inventory';
  static const String boards = 'boards';
  static const String history = 'history';
}

/// Common Firestore field names
abstract class FirestoreFields {
  // Inventory fields
  static const String partNumber = 'part_#';
  static const String type = 'type';
  static const String value = 'value';
  static const String package = 'package';
  static const String description = 'description';
  static const String qty = 'qty';
  static const String location = 'location';
  static const String pricePerUnit = 'price_per_unit';
  static const String notes = 'notes';
  static const String vendorLink = 'vendor_link';
  static const String datasheet = 'datasheet';
  static const String lastUpdated = 'last_updated';

  // Board fields
  static const String name = 'name';
  static const String category = 'category';
  static const String color = 'color';
  static const String imageUrl = 'imageUrl';
  static const String bom = 'bom';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';

  // BOM line fields
  static const String requiredAttributes = 'required_attributes';
  static const String selectedComponentRef = 'selected_component_ref';

  // History fields
  static const String action = 'action';
  static const String boardId = 'board_id';
  static const String boardName = 'board_name';
  static const String quantity = 'quantity';
  static const String timestamp = 'timestamp';
  static const String bomSnapshot = 'bom_snapshot';
}

/// Action type strings stored in history documents
abstract class HistoryActions {
  static const String makeBoard = 'make_board';
  static const String editItem = 'edit_item';
  static const String deleteItem = 'delete_item';
  static const String addItem = 'add_item';
  static const String importCsv = 'import_csv';
}

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
  static const String consumedItems = 'consumed_items';
  static const String skippedLines = 'skipped_lines';
  static const String undoneAt = 'undone_at';

  // Edit / delete / add history fields
  static const String editedField = 'field';
  static const String oldValue = 'old_value';
  static const String newValue = 'new_value';
  static const String itemSnapshot = 'item_snapshot';

  // CSV import history fields
  static const String itemCount = 'item_count';
  static const String addedItems = 'added_items';
  static const String updatedItems = 'updated_items';
  static const String importAction = 'import_action';
  static const String oldSnapshot = 'old_snapshot';
  static const String newSnapshot = 'new_snapshot';

  // Utility fields
  static const String docId = 'doc_id';
}

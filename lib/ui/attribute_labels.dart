const Map<String, String> kAttrLabel = {
  'qty': 'Qty',
  'part_type': 'Type',
  'size': 'Size',
  'value': 'Value',
  'part_#': 'Part #',
  'category': 'Category',
  'description': 'Description',
  'location': 'Location',
  'notes': 'Notes',
  'datasheet': 'Datasheet',
  'name': 'Name',
  'updatedAt': 'Last Updated',
  'createdAt': 'Created At',
};

String attrLabel(String? key) {
  if (key == null) return '';
  return kAttrLabel[key.split('.').last] ?? key;
}

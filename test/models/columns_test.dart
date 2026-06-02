import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/models/columns.dart';

void main() {
  group('columns model', () {
    test('attrLabel handles null, nested, and unknown keys', () {
      expect(attrLabel(null), '');
      expect(attrLabel('required_attributes.qty'), 'Qty');
      expect(attrLabel('unknown_key'), 'unknown_key');
    });

    test('ColumnSpec uses inferred label when label is empty', () {
      final spec = ColumnSpec(field: 'required_attributes.value');
      expect(spec.label, 'Value');
    });

    test('ColumnSpec keeps explicit label and options provider', () async {
      final providerCalls = <Map<String, dynamic>>[];
      final spec = ColumnSpec(
        field: 'required_attributes.selected_component_ref',
        label: 'Component',
        kind: CellKind.dropdown,
        dropdownOptionsProvider: (row) async {
          providerCalls.add(row);
          return [
            {'id': 'abc', 'label': 'ABC'},
          ];
        },
      );

      final options = await spec.dropdownOptionsProvider!.call({'k': 'v'});
      expect(spec.label, 'Component');
      expect(spec.kind, CellKind.dropdown);
      expect(options.single['id'], 'abc');
      expect(providerCalls.single['k'], 'v');
    });

    test('UnifiedInventoryColumns defines expected fields and kinds', () {
      final all = UnifiedInventoryColumns.all;
      expect(all.length, 11);

      expect(all.first.field, 'part_#');
      expect(all[1].field, 'digikey_part_#');
      expect(all[6].field, 'qty');
      expect(all[6].kind, CellKind.integer);
      expect(all[8].field, 'price_per_unit');
      expect(all[8].kind, CellKind.decimal);
      expect(all.last.field, 'vendor_link');
      expect(all.last.kind, CellKind.url);
    });
  });
}

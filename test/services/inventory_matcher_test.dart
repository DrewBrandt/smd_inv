import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/services/inventory_matcher.dart';

void main() {
  group('InventoryMatcher', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();

      // Add test inventory data
      await fakeFirestore.collection('inventory').add({
        'part_#': 'R100',
        'type': 'resistor',
        'value': '10k',
        'package': '0603',
        'description': 'Resistor 10k 0603 1%',
        'qty': 500,
      });

      await fakeFirestore.collection('inventory').add({
        'part_#': 'C100',
        'type': 'capacitor',
        'value': '10u',
        'package': '0805',
        'description': 'Capacitor 10uF 0805 X7R',
        'qty': 200,
      });

      await fakeFirestore.collection('inventory').add({
        'part_#': 'IC-STM32F103',
        'type': 'ic',
        'value': null,
        'package': 'LQFP-48',
        'description': 'STM32F103 MCU',
        'qty': 50,
      });

      await fakeFirestore.collection('inventory').add({
        'part_#': 'C200',
        'type': 'capacitor',
        'value': '10u',
        'package': '0805',
        'description': 'Another 10uF cap (duplicate for testing)',
        'qty': 100,
      });
    });

    group('findMatches() - Strategy 1: selected_component_ref', () {
      test('matches by selected_component_ref document ID', () async {
        final inventory = await fakeFirestore.collection('inventory').get();
        final firstDocId = inventory.docs[0].id;

        final bomAttributes = {
          'selected_component_ref': firstDocId,
          'part_#': 'WRONG_PART',
          'part_type': 'resistor',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('ignores invalid selected_component_ref', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'selected_component_ref': 'invalid-doc-id-12345',
          'part_#': 'R100', // Should fall back to part# match
          'part_type': 'resistor',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should fall back to part# matching
        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('handles empty selected_component_ref', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'selected_component_ref': '',
          'part_#': 'C100',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should fall back to part# matching
        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'C100');
      });
    });

    group('findMatches() - Strategy 2: part number exact match', () {
      test('matches by exact part number', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'R100',
          'part_type': 'resistor',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
        expect(matches.first.data()['qty'], 500);
      });

      test('matches part number case-insensitively', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'r100', // lowercase
          'part_type': 'resistor',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('trims whitespace from part numbers', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': '  R100  ',
          'part_type': 'resistor',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('returns empty list when part number not found', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'NONEXISTENT',
          'part_type': 'resistor',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches, isEmpty);
      });
    });

    group('findMatches() - Strategy 3: passive matching (type+value+size)',
        () {
      test('matches capacitor by type+value+size', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': '', // No part number
          'part_type': 'capacitor',
          'value': '10u',
          'size': '0805',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should find 2 matching 10u 0805 capacitors
        expect(matches.length, 2);
        expect(matches.every((m) => m.data()['type'] == 'capacitor'), true);
        expect(matches.every((m) => m.data()['value'] == '10u'), true);
        expect(matches.every((m) => m.data()['package'] == '0805'), true);
      });

      test('matches resistor by type+value+size', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_type': 'resistor',
          'value': '10k',
          'size': '0603',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('does not match passives without value', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_type': 'capacitor',
          'value': '', // Missing value
          'size': '0805',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches, isEmpty);
      });

      test('does not match ICs by type+value+size (non-passive)', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_type': 'ic',
          'value': 'some-value',
          'size': 'LQFP-48',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should not match because IC is not a passive
        expect(matches, isEmpty);
      });

      test('matches package case-insensitively', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_type': 'resistor',
          'value': '10k',
          'size': '0603', // lowercase vs uppercase in DB
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches.length, 1);
      });
    });

    group('findBestMatch()', () {
      test('returns single match when exactly one found', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'R100',
        };

        final bestMatch = await InventoryMatcher.findBestMatch(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(bestMatch, isNotNull);
        expect(bestMatch!.data()['part_#'], 'R100');
      });

      test('returns null when multiple ambiguous matches', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_type': 'capacitor',
          'value': '10u',
          'size': '0805',
        };

        final bestMatch = await InventoryMatcher.findBestMatch(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should return null because there are 2 matching capacitors
        expect(bestMatch, isNull);
      });

      test('returns null when no match found', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'NONEXISTENT',
        };

        final bestMatch = await InventoryMatcher.findBestMatch(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(bestMatch, isNull);
      });
    });

    group('getMatchResult()', () {
      test('returns exactMatch result for single match', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'R100',
        };

        final result = await InventoryMatcher.getMatchResult(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(result.type, MatchType.exactMatch);
        expect(result.hasMatch, true);
        expect(result.isExact, true);
        expect(result.isAmbiguous, false);
        expect(result.notFound, false);
        expect(result.singleMatch, isNotNull);
        expect(result.singleMatch!.data()['part_#'], 'R100');
      });

      test('returns multipleMatches result for ambiguous matches', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_type': 'capacitor',
          'value': '10u',
          'size': '0805',
        };

        final result = await InventoryMatcher.getMatchResult(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(result.type, MatchType.multipleMatches);
        expect(result.hasMatch, true);
        expect(result.isExact, false);
        expect(result.isAmbiguous, true);
        expect(result.matches.length, 2);
        expect(result.singleMatch, isNull);
      });

      test('returns notFound result when no match', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'NONEXISTENT',
        };

        final result = await InventoryMatcher.getMatchResult(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(result.type, MatchType.notFound);
        expect(result.hasMatch, false);
        expect(result.isExact, false);
        expect(result.notFound, true);
        expect(result.matches, isEmpty);
      });
    });

    group('makePartLabel()', () {
      test('uses part number when available', () {
        final attrs = {
          'part_#': 'R100',
          'part_type': 'resistor',
          'value': '10k',
          'size': '0603',
        };

        final label = InventoryMatcher.makePartLabel(attrs);

        expect(label, 'R100');
      });

      test('constructs label from type+value+size when no part number', () {
        final attrs = {
          'part_#': '',
          'part_type': 'resistor',
          'value': '10k',
          'size': '0603',
        };

        final label = InventoryMatcher.makePartLabel(attrs);

        expect(label, 'resistor 10k 0603');
      });

      test('handles partial attributes', () {
        final attrs = {
          'part_type': 'capacitor',
          'value': '10u',
        };

        final label = InventoryMatcher.makePartLabel(attrs);

        expect(label, 'capacitor 10u');
      });

      test('returns "Unknown part" for empty attributes', () {
        final attrs = <String, dynamic>{};

        final label = InventoryMatcher.makePartLabel(attrs);

        expect(label, 'Unknown part');
      });

      test('ignores empty values', () {
        final attrs = {
          'part_type': 'resistor',
          'value': '',
          'size': '0603',
        };

        final label = InventoryMatcher.makePartLabel(attrs);

        expect(label, 'resistor 0603');
      });
    });

    group('Integration: Strategy priority', () {
      test('prefers selected_component_ref over part number', () async {
        final inventory = await fakeFirestore.collection('inventory').get();
        final resistorDocId = inventory.docs
            .firstWhere((doc) => doc.data()['part_#'] == 'R100')
            .id;

        final bomAttributes = {
          'selected_component_ref': resistorDocId,
          'part_#': 'C100', // Different part number, should be ignored
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should match R100 (from ref), not C100 (from part#)
        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('falls back from part# to passive matching', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'UNKNOWN_PART',
          'part_type': 'resistor',
          'value': '10k',
          'size': '0603',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        // Should fall back to type+value+size matching
        expect(matches.length, 1);
        expect(matches.first.data()['part_#'], 'R100');
      });

      test('returns empty when all strategies fail', () async {
        final inventory = await fakeFirestore.collection('inventory').get();

        final bomAttributes = {
          'part_#': 'UNKNOWN',
          'part_type': 'diode', // Not in inventory
          'value': '1N4148',
          'size': 'SOD-123',
        };

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: bomAttributes,
          inventorySnapshot: inventory,
          firestore: fakeFirestore,
        );

        expect(matches, isEmpty);
      });
    });
  });
}

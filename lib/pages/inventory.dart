// lib/pages/inventory.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/widgets/unified_inventory_grid.dart';
import 'package:smd_inv/widgets/manual_add_dialog.dart';
import 'package:smd_inv/widgets/csv_import_dialog.dart';
import '../constants/firestore_constants.dart';

class FullList extends StatefulWidget {
  const FullList({super.key});

  @override
  State<FullList> createState() => _FullListState();
}

class _FullListState extends State<FullList> {
  String _searchQuery = '';

  // Filter states
  Set<String> _selectedTypes = {};
  Set<String> _selectedPackages = {};
  Set<String> _selectedLocations = {};

  // Available filter values (will be populated from Firestore)
  List<String> _availableTypes = [];
  List<String> _availablePackages = [];
  List<String> _availableLocations = [];

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    // Get unique values for filters
    final snapshot = await FirebaseFirestore.instance.collection(FirestoreCollections.inventory).get();

    final types = <String>{};
    final packages = <String>{};
    final locations = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data[FirestoreFields.type] != null) types.add(data[FirestoreFields.type].toString());
      if (data[FirestoreFields.package] != null && data[FirestoreFields.package].toString().isNotEmpty) {
        packages.add(data[FirestoreFields.package].toString());
      }
      if (data[FirestoreFields.location] != null && data[FirestoreFields.location].toString().isNotEmpty) {
        locations.add(data[FirestoreFields.location].toString());
      }
    }

    setState(() {
      _availableTypes = types.toList()..sort();
      _availablePackages = packages.toList()..sort();
      _availableLocations = locations.toList()..sort();
    });
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search (comma-separated for AND)',
                hintText: 'e.g., "ind, 0805" finds inductors with 0805 package',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(width: 12),
          MenuAnchor(
            builder: (context, controller, child) {
              return FilledButton.icon(
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              );
            },
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.edit_outlined),
                onPressed: _addManualRow,
                child: const Text('Add Manual Entry'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.upload_file_outlined),
                onPressed: _importCSV,
                child: const Text('Import from CSV'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Type filter
          _buildFilterMenu(
            icon: Icons.category_outlined,
            label: 'Type',
            selected: _selectedTypes,
            available: _availableTypes,
            onChanged: (selected) => setState(() => _selectedTypes = selected),
            formatLabel: (type) {
              // Format: IC stays caps, others capitalize first letter
              if (type.toLowerCase() == 'ic') return 'IC';
              return type[0].toUpperCase() + type.substring(1);
            },
          ),

          // Package filter
          _buildFilterMenu(
            icon: Icons.inventory_2_outlined,
            label: 'Package',
            selected: _selectedPackages,
            available: _availablePackages,
            onChanged: (selected) => setState(() => _selectedPackages = selected),
          ),

          // Location filter
          _buildFilterMenu(
            icon: Icons.location_on_outlined,
            label: 'Location',
            selected: _selectedLocations,
            available: _availableLocations,
            onChanged: (selected) => setState(() => _selectedLocations = selected),
          ),

          // Clear all filters
          if (_selectedTypes.isNotEmpty || _selectedPackages.isNotEmpty || _selectedLocations.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear Filters'),
              onPressed: () {
                setState(() {
                  _selectedTypes.clear();
                  _selectedPackages.clear();
                  _selectedLocations.clear();
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterMenu({
    required IconData icon,
    required String label,
    required Set<String> selected,
    required List<String> available,
    required ValueChanged<Set<String>> onChanged,
    String Function(String)? formatLabel,
  }) {
    return MenuAnchor(
      builder: (context, controller, child) {
        final count = selected.length;
        return FilterChip(
          avatar: Icon(icon, size: 18),
          label: Text(count > 0 ? '$label ($count)' : label),
          selected: count > 0,
          onSelected: (_) {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No options available', style: TextStyle(color: Colors.grey)),
          )
        else
          ...available.map((value) {
            final isSelected = selected.contains(value);
            final displayLabel = formatLabel?.call(value) ?? value;

            return CheckboxMenuButton(
              value: isSelected,
              onChanged: (checked) {
                final newSelected = Set<String>.from(selected);
                if (checked == true) {
                  newSelected.add(value);
                } else {
                  newSelected.remove(value);
                }
                onChanged(newSelected);
              },
              child: Text(displayLabel),
            );
          }),
      ],
    );
  }

  void _addManualRow() {
    showDialog(
      context: context,
      builder: (ctx) => const ManualAddDialog(),
    ).then((_) => _loadFilterOptions()); // Refresh filter options after adding
  }

  void _importCSV() {
    showDialog(
      context: context,
      builder: (ctx) => const CSVImportDialog(),
    ).then((_) => _loadFilterOptions()); // Refresh filter options after import
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
        child: Column(
          children: [
            _buildSearchBar(),
            _buildFilterChips(),
            Expanded(
              child: UnifiedInventoryGrid(
                searchQuery: _searchQuery,
                typeFilter: _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
                packageFilter: _selectedPackages.isEmpty ? null : _selectedPackages.toList(),
                locationFilter: _selectedLocations.isEmpty ? null : _selectedLocations.toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

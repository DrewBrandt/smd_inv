// lib/pages/inventory.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/widgets/unified_data_grid.dart';
import 'package:smd_inv/widgets/manual_add_dialog.dart';
import 'package:smd_inv/widgets/csv_import_dialog.dart';
import '../constants/firestore_constants.dart';
import '../models/columns.dart';

class FullList extends StatefulWidget {
  const FullList({super.key});

  @override
  State<FullList> createState() => _FullListState();
}

class _FullListState extends State<FullList> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterOptions() async {
    // Get unique values for filters
    final snapshot =
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.inventory)
            .get();

    final types = <String>{};
    final packages = <String>{};
    final locations = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data[FirestoreFields.type] != null) {
        types.add(data[FirestoreFields.type].toString());
      }
      if (data[FirestoreFields.package] != null &&
          data[FirestoreFields.package].toString().isNotEmpty) {
        packages.add(data[FirestoreFields.package].toString());
      }
      if (data[FirestoreFields.location] != null &&
          data[FirestoreFields.location].toString().isNotEmpty) {
        locations.add(data[FirestoreFields.location].toString());
      }
    }

    if (!mounted) return;
    setState(() {
      _availableTypes = types.toList()..sort();
      _availablePackages = packages.toList()..sort();
      _availableLocations = locations.toList()..sort();
    });
  }

  Widget _buildSearchBar(bool canEdit) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search (comma-separated for AND)',
                hintText: 'e.g., "ind, 0805" finds inductors with 0805 package',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchQuery.isEmpty
                        ? null
                        : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(width: 12),
          MenuAnchor(
            builder: (context, controller, child) {
              return FilledButton.icon(
                onPressed:
                    canEdit
                        ? () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        }
                        : null,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              );
            },
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.edit_outlined),
                onPressed: canEdit ? _addManualRow : null,
                child: const Text('Add Manual Entry'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.upload_file_outlined),
                onPressed: canEdit ? _importCSV : null,
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
      padding: const EdgeInsets.only(bottom: 10),
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
            onChanged:
                (selected) => setState(() => _selectedPackages = selected),
          ),

          // Location filter
          _buildFilterMenu(
            icon: Icons.location_on_outlined,
            label: 'Location',
            selected: _selectedLocations,
            available: _availableLocations,
            onChanged:
                (selected) => setState(() => _selectedLocations = selected),
          ),

          // Clear all filters
          if (_selectedTypes.isNotEmpty ||
              _selectedPackages.isNotEmpty ||
              _selectedLocations.isNotEmpty)
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No options available',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges(),
      initialData: AuthService.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        final canEdit = AuthService.canEdit(user);
        final cs = Theme.of(context).colorScheme;

        return Column(
          children: [
            if (!canEdit)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: cs.secondary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  user == null
                      ? 'View-only mode. Sign in with a UMD account to edit inventory.'
                      : 'Signed in as ${user.email}. View-only mode.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                children: [_buildSearchBar(canEdit), _buildFilterChips()],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: UnifiedDataGrid.inventory(
                columns: UnifiedInventoryColumns.all,
                searchQuery: _searchQuery,
                typeFilter:
                    _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
                packageFilter:
                    _selectedPackages.isEmpty
                        ? null
                        : _selectedPackages.toList(),
                locationFilter:
                    _selectedLocations.isEmpty
                        ? null
                        : _selectedLocations.toList(),
                allowEditing: canEdit,
                enableRowMenu: canEdit,
              ),
            ),
          ],
        );
      },
    );
  }
}

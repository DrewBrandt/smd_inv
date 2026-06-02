// lib/widgets/searchable_part_picker.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/firestore_constants.dart';

/// A searchable inventory part picker with an autofilling search box.
///
/// On open it prefills the search field from the BOM line's required
/// attributes (package / type / value) and filters the supplied inventory
/// options with AND logic across all fields. Used both inline in the BOM
/// editor grid and in the board-build "resolve substitute" dialog so the two
/// flows share identical autofill behavior.
class SearchablePartPicker extends StatefulWidget {
  final String currentValue;
  final Future<List<Map<String, String>>> Function(Map<String, dynamic> rowData)
  optionsProvider;
  final Map<String, dynamic> rowData;
  final ColorScheme colorScheme;
  final ValueChanged<String?> onChanged;

  /// When true the search box is rendered as an outlined form field (for use
  /// in dialogs). When false it is a borderless field sized for a grid cell.
  final bool outlined;

  /// Optional label shown above the field when [outlined] is true.
  final String? labelText;

  /// When true (the default, suited to a transient grid-cell editor) the field
  /// grabs focus and opens its results overlay as soon as options load. Set to
  /// false when several pickers share a screen (e.g. a dialog) so they don't
  /// all fight for focus — the overlay then opens only when the field is tapped.
  final bool autoOpen;

  const SearchablePartPicker({
    super.key,
    required this.currentValue,
    required this.optionsProvider,
    required this.rowData,
    required this.colorScheme,
    required this.onChanged,
    this.outlined = false,
    this.labelText,
    this.autoOpen = true,
  });

  /// Maps a raw inventory document into the option shape this picker expects.
  static Map<String, String> inventoryDocToOption(
    String id,
    Map<String, dynamic> data,
  ) {
    return {
      'id': id,
      'part_#': data[FirestoreFields.partNumber]?.toString() ?? '',
      'type': data[FirestoreFields.type]?.toString() ?? '',
      'value': data[FirestoreFields.value]?.toString() ?? '',
      'package': data[FirestoreFields.package]?.toString() ?? '',
      'qty': data[FirestoreFields.qty]?.toString() ?? '',
      'location': data[FirestoreFields.location]?.toString() ?? '',
      'description': data[FirestoreFields.description]?.toString() ?? '',
    };
  }

  @override
  State<SearchablePartPicker> createState() => _SearchablePartPickerState();
}

class _SearchablePartPickerState extends State<SearchablePartPicker> {
  List<Map<String, String>>? _allOptions;
  List<Map<String, String>> _filteredOptions = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  final _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterOptions);
    _focusNode.onKeyEvent = _handleKeyEvent;
    _loadOptions();
  }

  /// Swallow Escape while the results overlay is open so it dismisses just the
  /// dropdown, not the enclosing dialog (e.g. the board-build "Resolve BOM"
  /// dialog). When the overlay is already closed, let Escape propagate so the
  /// dialog can close as usual.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _overlayEntry != null) {
      _removeOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await widget.optionsProvider(widget.rowData);
      if (mounted) {
        // Pre-fill search box with type and value from BOM line
        // For non-ICs (passives), also include package
        final requiredAttrs =
            widget.rowData['required_attributes'] as Map<String, dynamic>?;
        final prefillTerms = <String>[];

        if (requiredAttrs != null) {
          final pkg = requiredAttrs['size']?.toString().trim() ?? '';
          final type = requiredAttrs['part_type']?.toString().trim() ?? '';
          final value = requiredAttrs['value']?.toString().trim() ?? '';
          final partNumber =
              requiredAttrs[FirestoreFields.partNumber]?.toString().trim() ?? '';

          // A concrete part number is the most reliable search term, so prefer
          // it alone. This matters for connectors whose `value` is a net label
          // (e.g. "I2C"/"UART") rather than the part — the picker should search
          // on the connector part number (e.g. "B4B-XH-A"), not "connector i2c".
          if (partNumber.isNotEmpty) {
            prefillTerms.add(partNumber);
          } else {
            // Only include package for non-ICs (passives like resistors, capacitors, etc.)
            if (pkg.isNotEmpty && type != 'ic') prefillTerms.add(pkg);
            if (type.isNotEmpty) prefillTerms.add(type);
            if (value.isNotEmpty) prefillTerms.add(value);
          }
        }

        final prefillText = prefillTerms.join(' ');

        setState(() {
          _allOptions = options;
          _filteredOptions = options;
          _loading = false;
          _searchController.text = prefillText;
        });
        // Apply the prefill as the initial filter.
        _filterOptions();
        // Auto-open dropdown after loading (skipped when several pickers share
        // a screen, so they don't all grab focus at once).
        if (widget.autoOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _focusNode.requestFocus();
              // Select all text so user can easily delete it
              _searchController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _searchController.text.length,
              );
              _showOverlay();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allOptions = [];
          _filteredOptions = [];
          _loading = false;
        });
      }
    }
  }

  void _filterOptions() {
    if (_allOptions == null) return;

    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredOptions = _allOptions!;
      } else {
        // Split query by spaces for AND logic (all terms must match)
        final terms =
            query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

        _filteredOptions =
            _allOptions!.where((option) {
              final id = option['id']?.toLowerCase() ?? '';
              final partNum = option['part_#']?.toLowerCase() ?? '';
              final type = option['type']?.toLowerCase() ?? '';
              final value = option['value']?.toLowerCase() ?? '';
              final pkg = option['package']?.toLowerCase() ?? '';
              final location = option['location']?.toLowerCase() ?? '';
              final description = option['description']?.toLowerCase() ?? '';

              // Combine all searchable fields
              final searchableText =
                  '$id $partNum $type $value $pkg $location $description';

              // ALL terms must be present (AND logic)
              return terms.every((term) => searchableText.contains(term));
            }).toList();
      }
    });

    // Update overlay if showing
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _showOverlay() {
    _removeOverlay();

    // Get the render box to determine width
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 300;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => Positioned(
            width: width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, widget.outlined ? 56 : 30),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount:
                        (widget.currentValue.isNotEmpty ? 1 : 0) +
                        (_filteredOptions.isEmpty ? 1 : _filteredOptions.length),
                    itemBuilder: (context, index) {
                      // "None" clear tile — only shown when a value is selected
                      if (widget.currentValue.isNotEmpty && index == 0) {
                        return _buildClearTile();
                      }
                      final adjustedIndex =
                          index - (widget.currentValue.isNotEmpty ? 1 : 0);
                      if (_filteredOptions.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No matches found',
                            style: TextStyle(
                              color: widget.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return _buildOptionTile(_filteredOptions[adjustedIndex]);
                    },
                  ),
                ),
              ),
            ),
          ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildClearTile() {
    return InkWell(
      onTap: () {
        _removeOverlay();
        widget.onChanged('');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: widget.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.link_off, size: 14, color: widget.colorScheme.error),
            const SizedBox(width: 8),
            Text(
              '— None (unpair) —',
              style: TextStyle(
                fontSize: 13,
                color: widget.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(Map<String, String> option) {
    final id = option['id'] ?? '';
    final partNum = option['part_#'] ?? '';
    final type = option['type'] ?? '';
    final value = option['value'] ?? '';
    final pkg = option['package'] ?? '';
    final qty = option['qty'] ?? '';
    final location = option['location'] ?? '';
    final description = option['description'] ?? '';

    final isSelected = id == widget.currentValue;

    // Build main display line: Package + Value (most important for passives)
    final mainParts = <String>[];
    if (pkg.isNotEmpty) mainParts.add(pkg);
    if (value.isNotEmpty) mainParts.add(value);
    final mainLine =
        mainParts.isNotEmpty
            ? mainParts.join(' ')
            : (description.isNotEmpty ? description : type);

    return InkWell(
      onTap: () {
        _removeOverlay();
        widget.onChanged(id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? widget.colorScheme.primaryContainer.withValues(alpha: 0.45)
                  : null,
          border: Border(
            bottom: BorderSide(color: widget.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main line: package + value (most important)
            Row(
              children: [
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: widget.colorScheme.primary,
                    ),
                  ),
                Expanded(
                  child: Text(
                    mainLine,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                // Stock indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStockColor(qty),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Qty: $qty',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Second line: part# (if available) + location
            Row(
              children: [
                if (partNum.isNotEmpty) ...[
                  Icon(
                    Icons.tag,
                    size: 12,
                    color: widget.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      partNum,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Icon(
                  Icons.location_on,
                  size: 12,
                  color: widget.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location.isEmpty ? '(no location)' : location,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStockColor(String qtyStr) {
    final qty = int.tryParse(qtyStr) ?? 0;
    if (qty == 0) return widget.colorScheme.error;
    if (qty < 10) return widget.colorScheme.secondary;
    return widget.colorScheme.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading matches...',
              style: TextStyle(
                fontSize: 12,
                color: widget.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_allOptions == null || _allOptions!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'No inventory matches found',
          style: TextStyle(
            color: widget.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      );
    }

    final decoration = InputDecoration(
      labelText: widget.outlined ? widget.labelText : null,
      hintText: 'Search ${_allOptions!.length} matches...',
      hintStyle: TextStyle(
        fontSize: 13,
        color: widget.colorScheme.onSurfaceVariant,
      ),
      isDense: true,
      contentPadding:
          widget.outlined
              ? const EdgeInsets.symmetric(vertical: 14, horizontal: 12)
              : const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      border: widget.outlined ? const OutlineInputBorder() : InputBorder.none,
      suffixIcon:
          _searchController.text.isNotEmpty
              ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () => _searchController.clear(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
              : const Icon(Icons.search, size: 16),
      suffixIconConstraints: const BoxConstraints(
        minWidth: 24,
        minHeight: 24,
      ),
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding:
            widget.outlined
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 8),
        child: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: widget.autoOpen,
          style: const TextStyle(fontSize: 14),
          decoration: decoration,
          onTap: () {
            if (_overlayEntry == null) _showOverlay();
          },
          onSubmitted: (_) {
            if (_searchController.text.trim().isEmpty) {
              widget.onChanged('');
            } else if (_filteredOptions.length == 1) {
              widget.onChanged(_filteredOptions.first['id']);
            }
            _removeOverlay();
          },
        ),
      ),
    );
  }
}

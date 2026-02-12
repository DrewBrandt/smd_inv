// lib/pages/boards_editor.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/widgets/boards_editor/frontmatter.dart';
import 'package:smd_inv/widgets/bom_import_widget.dart';
import '../data/boards_repo.dart';
import '../models/board.dart';
import 'package:smd_inv/widgets/unified_data_grid.dart';
import '../models/columns.dart';
import '../constants/firestore_constants.dart';
import '../services/inventory_matcher.dart';

class BoardEditorPage extends StatefulWidget {
  final String? boardId;
  final FirebaseFirestore? firestore;
  final BoardsRepo? boardsRepo;

  const BoardEditorPage({
    super.key,
    this.boardId,
    this.firestore,
    this.boardsRepo,
  });

  @override
  State<BoardEditorPage> createState() => _BoardEditorPageState();
}

class _BoardEditorPageState extends State<BoardEditorPage> {
  late final FirebaseFirestore _db;
  late final BoardsRepo _boardsRepo;
  bool _saving = false;
  bool _dirty = false;
  bool _isMatching = false;
  bool _showingImport = false;

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _image = TextEditingController();
  final _category = ValueNotifier<String?>('');

  List<Map<String, dynamic>> _bom = [];
  QuerySnapshot<Map<String, dynamic>>? _inventoryCache;

  @override
  void initState() {
    super.initState();
    _db = widget.firestore ?? FirebaseFirestore.instance;
    _boardsRepo = widget.boardsRepo ?? BoardsRepo(firestore: _db);
    _loadInventoryCache();
    if (widget.boardId != null) _load();
    _name.addListener(_markDirty);
    _desc.addListener(_markDirty);
    _category.addListener(_markDirty);
  }

  Future<void> _loadInventoryCache() async {
    _inventoryCache =
        await _db.collection(FirestoreCollections.inventory).get();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool _ensureCanEdit() {
    if (AuthService.canEdit(AuthService.currentUser)) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must sign in with a UMD account to edit boards.'),
        ),
      );
    }
    return false;
  }

  Future<void> _load() async {
    final snap =
        await _db
            .collection(FirestoreCollections.boards)
            .doc(widget.boardId)
            .get();
    if (!snap.exists) return;
    final b = BoardDoc.fromSnap(snap);
    setState(() {
      _name.text = b.name;
      _desc.text = b.description ?? '';
      _category.value = b.category;
      _image.text = b.imageUrl ?? '';
      _bom =
          b.bom.map((line) {
            final map = line.toMap();
            // Initialize missing flag for backward compatibility
            map['_ignored'] ??= false;
            return map;
          }).toList();
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (!_ensureCanEdit()) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);

    final ref =
        widget.boardId != null
            ? _db.collection(FirestoreCollections.boards).doc(widget.boardId)
            : _db.collection(FirestoreCollections.boards).doc();

    // Handle image upload if new image selected
    String? imageUrl = _image.text.trim().isEmpty ? null : _image.text.trim();

    final sanitizedBom = _sanitizeBomForSave(_bom);

    final now = FieldValue.serverTimestamp();
    final data = {
      FirestoreFields.name: _name.text.trim(),
      FirestoreFields.description:
          _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      FirestoreFields.category:
          (_category.value ?? '').isEmpty ? null : _category.value,
      FirestoreFields.imageUrl: imageUrl,
      FirestoreFields.bom: sanitizedBom,
      FirestoreFields.updatedAt: now,
      if (widget.boardId == null) FirestoreFields.createdAt: now,
    };

    await ref.set(data, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    context.go('/boards');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.boardId == null ? 'Board created' : 'Board updated',
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    if (!_dirty) return context.go('/boards');
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text(
              'You have unsaved changes. This will discard them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    if (ok == true && mounted) context.go('/boards');
  }

  Future<void> _cloneBoard() async {
    if (!_ensureCanEdit()) return;
    final sourceId = widget.boardId;
    if (sourceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save this board first, then clone it.')),
      );
      return;
    }

    try {
      final newId = await _boardsRepo.duplicateBoard(sourceId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cloned board: $newId')));
      context.go('/boards/$newId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Clone failed: $e')));
    }
  }

  Future<void> _deleteBoard() async {
    if (!_ensureCanEdit()) return;
    final boardId = widget.boardId;
    if (boardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This board is not saved yet.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Board?'),
            content: const Text(
              'This removes the board and its BOM from Firestore. Build history remains.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      await _boardsRepo.deleteBoard(boardId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Board deleted')));
      context.go('/boards');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _startImportBOM() {
    if (!_ensureCanEdit()) return;
    // Warn if replacing existing BOM
    if (_bom.isNotEmpty) {
      showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Replace BOM?'),
              content: const Text(
                'This will REPLACE your current BOM with the imported data.\n\n'
                'All existing lines will be removed and replaced with the new import.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx, true);
                    setState(() => _showingImport = true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                    foregroundColor: Theme.of(context).colorScheme.onTertiary,
                  ),
                  child: const Text('Replace'),
                ),
              ],
            ),
      );
    } else {
      setState(() => _showingImport = true);
    }
  }

  void _cancelImport() {
    setState(() => _showingImport = false);
  }

  void _completeImport(List<Map<String, dynamic>> imported) {
    if (!_ensureCanEdit()) return;
    setState(() {
      _bom = imported;
      _showingImport = false;
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${imported.length} BOM lines')),
    );
  }

  List<Map<String, dynamic>> _sanitizeBomForSave(
    List<Map<String, dynamic>> rawLines,
  ) {
    return rawLines.map(_sanitizeBomLine).toList();
  }

  Map<String, dynamic> _sanitizeBomLine(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    final rawRequired = Map<String, dynamic>.from(
      raw[FirestoreFields.requiredAttributes] as Map? ?? const {},
    );

    final required = <String, dynamic>{};
    for (final entry in rawRequired.entries) {
      final key = entry.key.toString();
      if (key.startsWith('_')) continue;
      required[key] = entry.value;
    }

    out['designators'] =
        raw['designators']?.toString().trim().isNotEmpty == true
            ? raw['designators'].toString().trim()
            : '?';
    out[FirestoreFields.qty] = _toInt(raw[FirestoreFields.qty], fallback: 1);
    out[FirestoreFields.requiredAttributes] = required;
    out['_ignored'] = raw['_ignored'] == true;

    final category = raw[FirestoreFields.category]?.toString().trim();
    if (category != null && category.isNotEmpty) {
      out[FirestoreFields.category] = category;
    }

    final description = raw[FirestoreFields.description]?.toString().trim();
    if (description != null && description.isNotEmpty) {
      out[FirestoreFields.description] = description;
    }

    final notes = raw[FirestoreFields.notes]?.toString();
    if (notes != null) out[FirestoreFields.notes] = notes;

    return out;
  }

  int _toInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _refreshMatching() async {
    if (!_ensureCanEdit()) return;
    if (_bom.isEmpty) return;

    setState(() => _isMatching = true);

    try {
      // Reload inventory
      await _loadInventoryCache();

      for (final line in _bom) {
        final attrs =
            line[FirestoreFields.requiredAttributes] as Map<String, dynamic>?;
        if (attrs == null) continue;

        final matches = await InventoryMatcher.findMatches(
          bomAttributes: attrs,
          inventorySnapshot: _inventoryCache,
        );

        String? currentRef = attrs[FirestoreFields.selectedComponentRef];

        if (matches.isEmpty) {
          // No matches - clear selection
          attrs[FirestoreFields.selectedComponentRef] = null;
          line['_match_status'] = 'missing';
        } else if (matches.length == 1) {
          // Single match - auto-select
          attrs[FirestoreFields.selectedComponentRef] = matches.first.id;
          line['_match_status'] = 'matched';
        } else {
          // Multiple matches - preserve if valid, otherwise mark ambiguous
          if (currentRef != null && matches.any((m) => m.id == currentRef)) {
            line['_match_status'] = 'matched';
          } else {
            attrs[FirestoreFields.selectedComponentRef] = null;
            line['_match_status'] = 'ambiguous';
          }
        }
      }

      setState(() {
        _isMatching = false;
        _dirty = true;
      });

      if (mounted) {
        final matched =
            _bom.where((l) => l['_match_status'] == 'matched').length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Re-paired: $matched of ${_bom.length} matched'),
          ),
        );
      }
    } catch (e) {
      setState(() => _isMatching = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _addBomLine() {
    if (!_ensureCanEdit()) return;
    setState(() {
      _bom.add({
        'designators': '?',
        'qty': 1,
        'notes': '',
        'description': '',
        'category': 'components',
        'required_attributes': {
          'part_type': '',
          'size': '',
          'value': '',
          'part_#': '',
          'selected_component_ref': null,
        },
        '_match_status': 'missing',
        '_ignored': false,
      });
      _markDirty();
    });
  }

  List<ColumnSpec> get _bomColumns => [
    ColumnSpec(
      field: '_ignored',
      label: 'Ignore',
      kind: CellKind.checkbox,
      editable: false,
      maxPercentWidth: 6,
    ),
    ColumnSpec(
      field: 'required_attributes.selected_component_ref',
      label: 'Component',
      kind: CellKind.dropdown,
      dropdownOptionsProvider: (rowData) async {
        // Return ALL inventory items for manual search/selection
        if (_inventoryCache == null) {
          await _loadInventoryCache();
        }

        if (_inventoryCache == null || _inventoryCache!.docs.isEmpty) {
          return [];
        }

        // Convert all inventory to dropdown options
        return _inventoryCache!.docs.map((doc) {
          final data = doc.data();
          final partNum = data['part_#']?.toString() ?? '';
          final type = data['type']?.toString() ?? '';
          final value = data['value']?.toString() ?? '';
          final pkg = data['package']?.toString() ?? '';
          final qty = data['qty']?.toString() ?? '';
          final location = data['location']?.toString() ?? '';
          final description = data['description']?.toString() ?? '';

          // Return all fields for rich display in dropdown
          return {
            'id': doc.id,
            'part_#': partNum,
            'type': type,
            'value': value,
            'package': pkg,
            'qty': qty,
            'location': location,
            'description': description,
          };
        }).toList();
      },
    ),
    ColumnSpec(field: 'designators', label: 'Designators'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ColumnSpec(
      field: 'required_attributes.part_type',
      label: 'Type',
      capitalize: true,
    ),
    ColumnSpec(field: 'required_attributes.value', label: 'Value'),
    ColumnSpec(field: 'required_attributes.size', label: 'Package'),
    ColumnSpec(field: 'description', label: 'Description'),
    ColumnSpec(field: 'notes', label: 'Notes'),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges(),
      initialData: AuthService.currentUser,
      builder: (context, authSnap) {
        final canEdit = AuthService.canEdit(authSnap.data);
        final cs = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            color: cs.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!canEdit)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'View-only mode. Sign in with a UMD account to edit board metadata or BOM lines.',
                            ),
                          ),
                        FrontmatterSection(
                          name: _name,
                          desc: _desc,
                          category: _category,
                          image: _image,
                          onClearImage:
                              () => setState(() {
                                _image.text = '';
                                _markDirty();
                              }),
                          onClone: _cloneBoard,
                          onDelete: _deleteBoard,
                          canEdit: canEdit,
                        ),
                        const Divider(height: 48),

                        Row(
                          children: [
                            Text(
                              'Bill of Materials',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(width: 12),
                            if (_bom.isNotEmpty) ...[
                              _buildStatusChip(
                                '${_bom.length} total',
                                cs.primary,
                              ),
                              const SizedBox(width: 8),
                              _buildStatusChip(
                                '${_bom.where((l) => l['_match_status'] == 'matched').length} matched',
                                cs.tertiary,
                              ),
                              if (_bom
                                  .where(
                                    (l) => l['_match_status'] == 'ambiguous',
                                  )
                                  .isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _buildStatusChip(
                                  '${_bom.where((l) => l['_match_status'] == 'ambiguous').length} ambiguous',
                                  cs.secondary,
                                ),
                              ],
                              if (_bom
                                  .where((l) => l['_match_status'] == 'missing')
                                  .isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _buildStatusChip(
                                  '${_bom.where((l) => l['_match_status'] == 'missing').length} missing',
                                  cs.error,
                                ),
                              ],
                            ],
                            const Spacer(),
                            if (_bom.isNotEmpty) ...[
                              OutlinedButton.icon(
                                onPressed:
                                    canEdit && !_isMatching
                                        ? _refreshMatching
                                        : null,
                                icon:
                                    _isMatching
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(Icons.refresh),
                                label: const Text('Re-pair All'),
                              ),
                              const SizedBox(width: 8),
                            ],
                            FilledButton.icon(
                              onPressed:
                                  canEdit && !_isMatching && !_showingImport
                                      ? _startImportBOM
                                      : null,
                              icon: const Icon(Icons.upload_file),
                              label: Text(
                                _bom.isEmpty ? 'Import BOM' : 'Replace BOM',
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: canEdit ? _addBomLine : null,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Line'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Workflow: import KiCad BOM, run Re-pair All, resolve remaining ambiguous/missing lines, then save.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_showingImport)
                          SizedBox(
                            height: 500,
                            child: BomImportWidget(
                              onCancel: _cancelImport,
                              onImport: _completeImport,
                            ),
                          )
                        else if (_bom.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(48),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 64,
                                    color: cs.outline,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No BOM lines yet',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Import from KiCad or add manually',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 500,
                            child: UnifiedDataGrid.local(
                              rows: _bom,
                              columns: _bomColumns,
                              persistKey:
                                  'bom_editor_${widget.boardId ?? 'new'}',
                              frozenColumnsCount: 2,
                              allowEditing: canEdit,
                              onRowsChanged: (updated) {
                                setState(() => _bom = updated);
                                _markDirty();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(16),
                  color: cs.surfaceContainerHighest,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _cancel,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: canEdit && !_saving && _dirty ? _save : null,
                        icon:
                            _saving
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                                : const Icon(Icons.save),
                        label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}

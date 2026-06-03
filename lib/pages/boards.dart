import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smd_inv/data/inventory_repo.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/models/digikey_part_info.dart';
import 'package:smd_inv/models/procurement.dart';
import 'package:smd_inv/models/readiness.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/services/board_build_service.dart';
import 'package:smd_inv/services/cart_paste_parser.dart';
import 'package:smd_inv/services/digikey_api_service.dart';
import 'package:smd_inv/services/digikey_part_resolver.dart';
import 'package:smd_inv/services/inventory_matcher.dart';
import 'package:smd_inv/services/procurement_planner_service.dart';
import 'package:smd_inv/services/readiness_calculator.dart';
import 'package:smd_inv/widgets/board_card.dart';
import 'package:smd_inv/widgets/searchable_part_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/firestore_constants.dart';
import '../data/boards_repo.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

enum BoardSortOption {
  nameAsc('Name (A–Z)'),
  recentlyAdded('Recently added'),
  recentlyUpdated('Recently updated'),
  mostComplete('Most complete'),
  mostBuildable('Most buildable');

  const BoardSortOption(this.label);
  final String label;

  static BoardSortOption fromName(String? name) {
    return BoardSortOption.values.firstWhere(
      (option) => option.name == name,
      orElse: () => BoardSortOption.nameAsc,
    );
  }
}

class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key});

  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage> {
  final BoardsRepo _repo = BoardsRepo();
  final InventoryRepo _inventoryRepo = InventoryRepo();
  final BoardBuildService _buildService = BoardBuildService();
  final ProcurementPlannerService _procurementPlanner =
      ProcurementPlannerService();
  final DigiKeyApiService _digikeyApi = DigiKeyApiService();
  final TextEditingController _boardSearchController = TextEditingController();
  final ScrollController _orderLinesHorizontalController = ScrollController();
  final ScrollController _lowStockHorizontalController = ScrollController();

  final Map<String, int> _boardCartQtyById = <String, int>{};
  final List<ManualProcurementLine> _manualLines = <ManualProcurementLine>[];
  final Map<String, int> _purchaseQtyOverrides = <String, int>{};
  final Map<String, String> _digikeyPnOverrides = <String, String>{};
  final Set<String> _deletedPlannerLineKeys = <String>{};
  final Set<String> _dismissedLowStockLineKeys = <String>{};
  final Set<String> _digikeyPnBackfillKeys = <String>{};

  /// Live DigiKey lookup results keyed by a line's preferred order identifier.
  final Map<String, DigiKeyPartInfo> _digikeyInfoByKey =
      <String, DigiKeyPartInfo>{};

  /// Identifiers already requested this session (success or failure) so we
  /// don't re-call the function repeatedly as the planner rebuilds.
  final Set<String> _digikeyRequestedKeys = <String>{};
  bool _digikeyLookupInFlight = false;

  String _boardSearchQuery = '';
  BoardSortOption _sortOption = BoardSortOption.nameAsc;

  static const String _sortPrefsKey = 'boards_sort_option';
  static const String _cartPrefsKey = 'boards_purchase_cart';
  static const String _manualLinesPrefsKey = 'boards_purchase_manual_lines';
  static const String _purchaseQtyPrefsKey = 'boards_purchase_qty_overrides';
  static const String _digikeyPnPrefsKey = 'boards_digikey_pn_overrides';
  static const String _deletedLinesPrefsKey =
      'boards_deleted_planner_line_keys';
  static const String _dismissedLowStockPrefsKey =
      'boards_dismissed_low_stock_line_keys';
  static const double _pageMaxWidth = 1600;
  static const double _pageHorizontalPadding = 16;
  static const double _pageVerticalPadding = 12;

  @override
  void initState() {
    super.initState();
    _boardSearchController.addListener(() {
      final next = _boardSearchController.text;
      if (next == _boardSearchQuery) return;
      setState(() => _boardSearchQuery = next);
    });
    _loadSavedSort();
    _loadSavedCart();
  }

  Future<void> _loadSavedSort() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = BoardSortOption.fromName(prefs.getString(_sortPrefsKey));
    if (!mounted || saved == _sortOption) return;
    setState(() => _sortOption = saved);
  }

  Future<void> _saveSort(BoardSortOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefsKey, option.name);
  }

  Future<void> _loadSavedCart() async {
    final prefs = await SharedPreferences.getInstance();
    final boardCart = _decodeStringIntMap(prefs.getString(_cartPrefsKey));
    final purchaseOverrides = _decodeStringIntMap(
      prefs.getString(_purchaseQtyPrefsKey),
    );
    final digiKeyOverrides = _decodeStringStringMap(
      prefs.getString(_digikeyPnPrefsKey),
    );
    final deletedLineKeys = _decodeStringList(
      prefs.getString(_deletedLinesPrefsKey),
    );
    final dismissedLowStockKeys = _decodeStringList(
      prefs.getString(_dismissedLowStockPrefsKey),
    );
    final manualLines = _decodeManualLines(
      prefs.getString(_manualLinesPrefsKey),
    );

    if (!mounted) return;
    setState(() {
      _boardCartQtyById
        ..clear()
        ..addAll(boardCart);
      _manualLines
        ..clear()
        ..addAll(manualLines);
      _purchaseQtyOverrides
        ..clear()
        ..addAll(purchaseOverrides);
      _digikeyPnOverrides
        ..clear()
        ..addAll(digiKeyOverrides);
      _deletedPlannerLineKeys
        ..clear()
        ..addAll(deletedLineKeys);
      _dismissedLowStockLineKeys
        ..clear()
        ..addAll(dismissedLowStockKeys);
    });
  }

  Future<void> _saveCartState() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_cartPrefsKey, jsonEncode(_boardCartQtyById)),
      prefs.setString(
        _manualLinesPrefsKey,
        jsonEncode(_manualLines.map((line) => line.toJson()).toList()),
      ),
      prefs.setString(_purchaseQtyPrefsKey, jsonEncode(_purchaseQtyOverrides)),
      prefs.setString(_digikeyPnPrefsKey, jsonEncode(_digikeyPnOverrides)),
      prefs.setString(
        _deletedLinesPrefsKey,
        jsonEncode(_deletedPlannerLineKeys.toList()),
      ),
      prefs.setString(
        _dismissedLowStockPrefsKey,
        jsonEncode(_dismissedLowStockLineKeys.toList()),
      ),
    ]);
  }

  static Map<String, int> _decodeStringIntMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final rawValue = entry.value;
        final value =
            rawValue is num ? rawValue.toInt() : int.tryParse('$rawValue');
        if (value != null && value > 0) {
          result[entry.key.toString()] = value;
        }
      }
      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  static Map<String, String> _decodeStringStringMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded.map((value) => value.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static List<ManualProcurementLine> _decodeManualLines(String? raw) {
    if (raw == null || raw.isEmpty) return <ManualProcurementLine>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ManualProcurementLine>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ManualProcurementLine.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((line) => line.quantity > 0)
          .toList();
    } catch (_) {
      return <ManualProcurementLine>[];
    }
  }

  @override
  void dispose() {
    _boardSearchController.dispose();
    _orderLinesHorizontalController.dispose();
    _lowStockHorizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges(),
      initialData: AuthService.currentUser,
      builder: (context, authSnap) {
        final canEdit = AuthService.canEdit(authSnap.data);

        return StreamBuilder<List<Doc>>(
          stream: _inventoryRepo.streamCollection(FirestoreCollections.boards),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final boards = snap.data!.map(BoardDoc.fromSnap).toList();
            final filteredBoards = _filterBoards(boards, _boardSearchQuery);

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance
                      .collection(FirestoreCollections.inventory)
                      .snapshots(),
              builder: (context, inventorySnap) {
                if (inventorySnap.hasError) {
                  return Center(child: Text('Error: ${inventorySnap.error}'));
                }
                if (!inventorySnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final inventory = inventorySnap.data!;
                final matcherIndex = InventoryMatcherIndex.fromSnapshot(
                  inventory,
                );
                final readinessByBoardId = {
                  for (final board in filteredBoards)
                    board.id: ReadinessCalculator.calculateSync(
                      board,
                      matcherIndex: matcherIndex,
                    ),
                };
                final sortedBoards = _sortBoards(
                  filteredBoards,
                  readinessByBoardId,
                );

                if (boards.isEmpty) {
                  return _buildEmptyState(canEdit);
                }

                return CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(
                      child: SizedBox(height: _pageVerticalPadding),
                    ),
                    if (!canEdit) _buildPageBoxSliver(_buildViewOnlyBanner()),
                    _buildPageBoxSliver(
                      _buildHeader(
                        canEdit,
                        totalBoardCount: boards.length,
                        visibleBoardCount: filteredBoards.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    _buildPageBoxSliver(
                      _buildProcurementPanel(
                        boards,
                        inventory,
                        canEdit: canEdit,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (filteredBoards.isEmpty)
                      SliverFillRemaining(
                        child: _buildPageContent(_buildNoSearchResults()),
                      )
                    else
                      SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final sidePadding =
                              _pageSidePadding(constraints.crossAxisExtent) + 4;
                          return SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: sidePadding,
                              vertical: 4,
                            ),
                            sliver: SliverGrid.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 420,
                                    childAspectRatio: 0.72,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                              itemCount: sortedBoards.length,
                              itemBuilder: (context, i) {
                                final b = sortedBoards[i];
                                final cartQty = _boardCartQtyById[b.id] ?? 0;
                                final readiness =
                                    readinessByBoardId[b.id] ??
                                    const Readiness(
                                      buildableQty: 0,
                                      readyPct: 0.0,
                                      shortfalls: [],
                                    );

                                return ImprovedBoardCard(
                                  board: b,
                                  readiness: readiness,
                                  canEdit: canEdit,
                                  cartQty: cartQty,
                                  onAddToCart:
                                      () => _showBoardCartDialog(context, b),
                                  onOpen: () => context.go('/boards/${b.id}'),
                                  onDuplicate: () async {
                                    if (!canEdit) return;
                                    final newId = await _repo.duplicateBoard(
                                      b.id,
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Cloned board: $newId'),
                                        showCloseIcon: true,
                                      ),
                                    );
                                  },
                                  onMake:
                                      canEdit
                                          ? (qty) => _makeBoards(
                                            context,
                                            b,
                                            qty,
                                            _buildService,
                                            inventory,
                                          )
                                          : null,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: _pageVerticalPadding),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPageBoxSliver(Widget child) {
    return SliverToBoxAdapter(child: _buildPageContent(child));
  }

  Widget _buildPageContent(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _pageHorizontalPadding,
          ),
          child: child,
        ),
      ),
    );
  }

  double _pageSidePadding(double crossAxisExtent) {
    final centeredPadding =
        ((crossAxisExtent - _pageMaxWidth) / 2) + _pageHorizontalPadding;
    return math.max(_pageHorizontalPadding, centeredPadding);
  }

  Widget _buildEmptyState(bool canEdit) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dashboard_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('No boards yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Create a board to track parts and build readiness'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: canEdit ? () => context.go('/boards/new') : null,
            icon: const Icon(Icons.add),
            label: const Text('Create First Board'),
          ),
        ],
      ),
    );
  }

  Widget _buildViewOnlyBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'View-only mode. Sign in with a UMD account to create, clone, or build boards.',
      ),
    );
  }

  Widget _buildHeader(
    bool canEdit, {
    required int totalBoardCount,
    required int visibleBoardCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    final boardCartCount = _boardCartQtyById.values.fold<int>(
      0,
      (total, qty) => total + qty,
    );
    final title =
        _boardSearchQuery.trim().isEmpty
            ? 'Boards ($totalBoardCount)'
            : 'Boards ($visibleBoardCount/$totalBoardCount)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        color: cs.surfaceContainer,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              _buildSortControl(cs),
              const SizedBox(width: 8),
              Chip(
                avatar: const Icon(Icons.shopping_cart_outlined, size: 16),
                label: Text('Cart $boardCartCount'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: canEdit ? () => context.go('/boards/new') : null,
                icon: const Icon(Icons.add),
                label: const Text('New Board'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _boardSearchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search boards by name, category, or part type',
              suffixIcon:
                  _boardSearchQuery.isEmpty
                      ? null
                      : IconButton(
                        onPressed: _boardSearchController.clear,
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                      ),
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: cs.surface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortControl(ColorScheme cs) {
    return PopupMenuButton<BoardSortOption>(
      tooltip: 'Sort boards',
      initialValue: _sortOption,
      onSelected: (option) {
        if (option == _sortOption) return;
        setState(() => _sortOption = option);
        _saveSort(option);
      },
      itemBuilder:
          (context) =>
              BoardSortOption.values
                  .map(
                    (option) => PopupMenuItem<BoardSortOption>(
                      value: option,
                      child: Row(
                        children: [
                          Icon(
                            option == _sortOption ? Icons.check : Icons.sort,
                            size: 16,
                            color:
                                option == _sortOption
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(option.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
          color: cs.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 16),
            const SizedBox(width: 6),
            Text('Sort: ${_sortOption.label}'),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResults() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            'No boards match "${_boardSearchQuery.trim()}"',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different board name, category, or part type.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<BoardDoc> _sortBoards(
    List<BoardDoc> boards,
    Map<String, Readiness> readinessByBoardId,
  ) {
    final sorted = List<BoardDoc>.from(boards);
    int byName(BoardDoc a, BoardDoc b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    // Newest first; boards without a timestamp fall to the bottom.
    int byDateDesc(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    switch (_sortOption) {
      case BoardSortOption.nameAsc:
        sorted.sort(byName);
      case BoardSortOption.recentlyAdded:
        sorted.sort((a, b) {
          final c = byDateDesc(a.createdAt, b.createdAt);
          return c != 0 ? c : byName(a, b);
        });
      case BoardSortOption.recentlyUpdated:
        sorted.sort((a, b) {
          final c = byDateDesc(a.updatedAt, b.updatedAt);
          return c != 0 ? c : byName(a, b);
        });
      case BoardSortOption.mostComplete:
        sorted.sort((a, b) {
          final ra = readinessByBoardId[a.id];
          final rb = readinessByBoardId[b.id];
          final c = (rb?.readyPct ?? 0).compareTo(ra?.readyPct ?? 0);
          if (c != 0) return c;
          final cq = (rb?.buildableQty ?? 0).compareTo(ra?.buildableQty ?? 0);
          return cq != 0 ? cq : byName(a, b);
        });
      case BoardSortOption.mostBuildable:
        sorted.sort((a, b) {
          final ra = readinessByBoardId[a.id];
          final rb = readinessByBoardId[b.id];
          final c = (rb?.buildableQty ?? 0).compareTo(ra?.buildableQty ?? 0);
          return c != 0 ? c : byName(a, b);
        });
    }
    return sorted;
  }

  List<BoardDoc> _filterBoards(List<BoardDoc> boards, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return boards;

    final terms =
        query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
    if (terms.isEmpty) return boards;

    return boards.where((board) {
      final bomTypes = board.bom
          .map(
            (line) =>
                line.requiredAttributes['part_type']?.toString().trim() ?? '',
          )
          .where((value) => value.isNotEmpty)
          .join(' ');
      final searchable =
          [
            board.name,
            board.category ?? '',
            board.description ?? '',
            bomTypes,
          ].join(' ').toLowerCase();
      return terms.every(searchable.contains);
    }).toList();
  }

  Widget _buildProcurementPanel(
    List<BoardDoc> boards,
    QuerySnapshot<Map<String, dynamic>> inventory, {
    required bool canEdit,
  }) {
    final cs = Theme.of(context).colorScheme;
    final maxPanelHeight = (MediaQuery.sizeOf(context).height * 0.58).clamp(
      260.0,
      560.0,
    );
    final boardOrders = _toBoardOrders(boards);
    final hasAnyCartItems = boardOrders.isNotEmpty || _manualLines.isNotEmpty;

    if (!hasAnyCartItems) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          color: cs.surfaceContainer,
        ),
        child: _buildPlannerPlaceholder(),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        color: cs.surfaceContainer,
      ),
      child: FutureBuilder<ProcurementPlan>(
        future: _procurementPlanner.buildPlan(
          boardOrders: boardOrders,
          inventorySnapshot: inventory,
        ),
        builder: (context, planSnap) {
          if (!planSnap.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final basePlan = planSnap.data!;
          final mergedPlan = _applyPlannerOverrides(
            ProcurementPlannerService.mergeManualLines(basePlan, _manualLines),
          );
          _queueDigiKeyEnrichment(mergedPlan, canEdit: canEdit);
          final plan = _applyDigiKeyEnrichment(mergedPlan);
          _queueDigiKeyPartNumberBackfill(plan, inventory, canEdit: canEdit);
          final orderLines = plan.orderableLines;
          final allLowStockLines = plan.lowStockLines;
          final lowStockLines = allLowStockLines
              .where(
                (line) =>
                    !_dismissedLowStockLineKeys.contains(
                      _lowStockLineKey(line),
                    ),
              )
              .toList(growable: false);
          final hiddenLowStockCount =
              allLowStockLines.length - lowStockLines.length;
          final nonExportable =
              orderLines.where((l) => !l.hasOrderIdentifier).length;
          final totalLinesInCart =
              _boardCartQtyById.length + _manualLines.length;

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPanelHeight),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Purchase Planner ($totalLinesInCart)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 10),
                      Chip(
                        avatar: const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                        ),
                        label: Text(
                          '${plan.unresolvedCount} unresolved, ${plan.ambiguousCount} ambiguous',
                        ),
                      ),
                      if (_digikeyLookupInFlight) ...[
                        const SizedBox(width: 10),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Looking up DigiKey…',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _clearCart,
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear Cart'),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: () => _showAddInventoryLineDialog(inventory),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Add Inventory Item'),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: _showPasteCartDialog,
                        icon: const Icon(Icons.content_paste_go_outlined),
                        label: const Text('Paste Cart'),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: _showAddManualLineDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Custom Line'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SummaryChip(
                        icon: Icons.list_alt_rounded,
                        label: 'Needed',
                        value: '${plan.totalRequiredQty}',
                      ),
                      _SummaryChip(
                        icon: Icons.shopping_cart_checkout_rounded,
                        label: 'To Order',
                        value: '${plan.totalShortageQty}',
                      ),
                      _SummaryChip(
                        icon: Icons.receipt_long_rounded,
                        label: 'Orderable Lines',
                        value:
                            '${plan.exportableLines.length}/${orderLines.length}',
                      ),
                      _SummaryChip(
                        icon: Icons.monetization_on_outlined,
                        label: 'Known Cost',
                        value: '\$${plan.knownOrderCost.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_boardCartQtyById.isNotEmpty)
                    _buildBoardCartSection(boards),
                  if (_manualLines.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildManualLinesSection(),
                  ],
                  if (plan.issues.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildIssuesSection(plan),
                  ],
                  if (lowStockLines.isNotEmpty || hiddenLowStockCount > 0) ...[
                    const SizedBox(height: 12),
                    _buildLowStockSection(
                      lowStockLines,
                      hiddenCount: hiddenLowStockCount,
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (orderLines.isEmpty)
                    const Text('No shortages detected for current cart.')
                  else
                    _buildOrderLinesTable(orderLines),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed:
                            plan.exportableLines.isEmpty
                                ? null
                                : () => _copyDigiKeyCsv(plan),
                        icon: const Icon(Icons.copy_all_rounded),
                        label: const Text('Copy DigiKey CSV'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed:
                            plan.exportableLines.isEmpty
                                ? null
                                : () => _copyQuickOrder(plan),
                        icon: const Icon(Icons.content_copy_rounded),
                        label: const Text('Copy Quick-Order Text'),
                      ),
                      if (nonExportable > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$nonExportable line(s) have no DigiKey/MPN identifier and are excluded from export.',
                            style: TextStyle(color: cs.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlannerPlaceholder() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Purchase Planner',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Add boards to cart from board cards, then generate a DigiKey-ready order list.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _showAddManualLineDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Custom Line'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _showPasteCartDialog,
              icon: const Icon(Icons.content_paste_go_outlined),
              label: const Text('Paste Cart'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBoardCartSection(List<BoardDoc> boards) {
    final byId = {for (final b in boards) b.id: b};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Board Cart', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _boardCartQtyById.entries.map((entry) {
                final board = byId[entry.key];
                final name = board?.name ?? entry.key;
                return InputChip(
                  label: Text('$name x${entry.value}'),
                  onPressed:
                      board == null
                          ? null
                          : () => _showBoardCartDialog(context, board),
                  onDeleted: () => _removeBoardFromCart(entry.key),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildManualLinesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ad-hoc Cart Lines',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ..._manualLines.asMap().entries.map((entry) {
          final idx = entry.key;
          final line = entry.value;
          final id =
              (line.digikeyPartNumber ?? '').isNotEmpty
                  ? line.digikeyPartNumber!
                  : line.partNumber;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('$id x${line.quantity}'),
            subtitle: Text(line.description),
            trailing: IconButton(
              onPressed: () => _removeManualLineAt(idx),
              icon: const Icon(Icons.delete_outline),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildIssuesSection(ProcurementPlan plan) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            plan.issues.map((issue) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '[${issue.typeLabel}] ${issue.partLabel} - qty ${issue.requiredQty} (${issue.boardNames.join(', ')})',
                  style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildLowStockSection(
    List<ProcurementLine> lines, {
    required int hiddenCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Low Stock',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if (hiddenCount > 0) ...[
                const SizedBox(width: 8),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$hiddenCount dismissed'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _restoreDismissedLowStock,
                  icon: const Icon(Icons.undo_outlined, size: 16),
                  label: const Text('Restore dismissed'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (lines.isEmpty)
            Text(
              'All low-stock suggestions are dismissed.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          else
            Scrollbar(
              controller: _lowStockHorizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              interactive: true,
              thickness: 10,
              radius: const Radius.circular(6),
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                controller: _lowStockHorizontalController,
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DataTable(
                    columnSpacing: 18,
                    horizontalMargin: 8,
                    columns: const [
                      DataColumn(label: Text('Part')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Value')),
                      DataColumn(label: Text('Stock')),
                      DataColumn(label: Text('Need')),
                      DataColumn(label: Text('Left')),
                      DataColumn(label: Text('Target')),
                      DataColumn(label: Text('Buy')),
                      DataColumn(label: Text('Dismiss')),
                      DataColumn(label: Text('Boards')),
                    ],
                    rows:
                        lines.map((line) {
                          return DataRow(
                            cells: [
                              DataCell(_buildPartCell(line, width: 180)),
                              DataCell(
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    line.partType.isEmpty ? '-' : line.partType,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    line.value.isEmpty ? '-' : line.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text('${line.inStockQty}')),
                              DataCell(Text('${line.requiredQty}')),
                              DataCell(Text('${line.remainingAfterRequired}')),
                              DataCell(
                                Text('${line.lowStockThreshold ?? '-'}'),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: 'Add this part to the order',
                                  onPressed: () => _showPurchaseQtyDialog(line),
                                  icon: const Icon(
                                    Icons.add_shopping_cart_outlined,
                                  ),
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: 'Dismiss low-stock suggestion',
                                  onPressed: () => _dismissLowStockLine(line),
                                  icon: const Icon(
                                    Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    line.boardNames.join(', '),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderLinesTable(List<ProcurementLine> lines) {
    return Scrollbar(
      controller: _orderLinesHorizontalController,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 10,
      radius: const Radius.circular(6),
      scrollbarOrientation: ScrollbarOrientation.bottom,
      child: SingleChildScrollView(
        controller: _orderLinesHorizontalController,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DataTable(
            columnSpacing: 18,
            horizontalMargin: 8,
            columns: const [
              DataColumn(label: Text('')),
              DataColumn(label: Text('Part')),
              DataColumn(label: Text('DigiKey PN')),
              DataColumn(label: Text('DigiKey')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Value')),
              DataColumn(label: Text('Pkg')),
              DataColumn(label: Text('Need')),
              DataColumn(label: Text('Stock')),
              DataColumn(label: Text('DK Stock')),
              DataColumn(label: Text('Buy')),
              DataColumn(label: Text('Source')),
              DataColumn(label: Text('Boards')),
            ],
            rows:
                lines.map((line) {
                  final digikeyPn = line.digikeyPartNumber?.trim() ?? '';
                  return DataRow(
                    cells: [
                      DataCell(
                        IconButton(
                          tooltip: 'Delete line',
                          onPressed: () => _deletePlannerLine(line),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                      DataCell(_buildPartCell(line, width: 180)),
                      DataCell(_buildDigiKeyPnCell(line, digikeyPn)),
                      DataCell(_buildDigiKeyStatus(line)),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: Text(
                            line.partType.isEmpty ? '-' : line.partType,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: Text(
                            line.value.isEmpty ? '-' : line.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: Text(
                            line.package.isEmpty ? '-' : line.package,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text('${line.requiredQty}')),
                      DataCell(Text('${line.inStockQty}')),
                      DataCell(_buildDigiKeyStockCell(line)),
                      DataCell(
                        TextButton.icon(
                          onPressed: () => _showPurchaseQtyDialog(line),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: Text('${line.purchaseQty}'),
                        ),
                      ),
                      DataCell(Text(_sourceLabel(line.source))),
                      DataCell(
                        SizedBox(
                          width: 150,
                          child: Text(
                            line.boardNames.join(', '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPartCell(ProcurementLine line, {required double width}) {
    final id = line.partNumber.isEmpty ? '-' : line.partNumber;
    return Tooltip(
      message: _partDetailsTooltip(line),
      child: SizedBox(
        width: width,
        child: Text(id, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  String _partDetailsTooltip(ProcurementLine line) {
    final details = <String>[];
    if (line.partNumber.trim().isNotEmpty) {
      details.add('Part: ${line.partNumber.trim()}');
    }
    final dk = line.digikeyPartNumber?.trim() ?? '';
    if (dk.isNotEmpty) details.add('DigiKey PN: $dk');
    if (line.partType.trim().isNotEmpty) {
      details.add('Type: ${line.partType.trim()}');
    }
    if (line.value.trim().isNotEmpty) {
      details.add('Value: ${line.value.trim()}');
    }
    if (line.package.trim().isNotEmpty) {
      details.add('Package: ${line.package.trim()}');
    }
    if (line.description.trim().isNotEmpty) {
      details.add('Description: ${line.description.trim()}');
    }
    return details.isEmpty ? 'No part details' : details.join('\n');
  }

  Widget _buildDigiKeyPnCell(ProcurementLine line, String digikeyPn) {
    if (digikeyPn.isEmpty) {
      return TextButton.icon(
        onPressed: () => _showDigiKeyPnDialog(line),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Add PN'),
      );
    }

    return TextButton.icon(
      onPressed: () => _showDigiKeyPnDialog(line),
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: SizedBox(
        width: 120,
        child: Text(digikeyPn, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildDigiKeyStockCell(ProcurementLine line) {
    final cs = Theme.of(context).colorScheme;
    final stock = line.digikeyStock;
    if (stock == null) {
      return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
    }
    if (line.digikeyOutOfStock) {
      return Tooltip(
        message:
            'DigiKey stock ($stock) is below the ${line.purchaseQty} needed — '
            'consider a replacement part.',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 16),
            const SizedBox(width: 4),
            Text(
              '$stock',
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return Text('$stock');
  }

  Widget _buildDigiKeyStatus(ProcurementLine line) {
    final cs = Theme.of(context).colorScheme;
    if (line.hasDigiKeyPartNumber) {
      return Tooltip(
        message: 'DigiKey part number is set',
        child: Icon(Icons.check_circle, color: cs.primary, size: 20),
      );
    }

    return Tooltip(
      message: 'Open DigiKey search',
      child: IconButton(
        onPressed: () => _openDigiKeySearch(line),
        icon: Icon(Icons.manage_search_rounded, color: cs.error, size: 20),
      ),
    );
  }

  /// Kicks off DigiKey lookups for any cart line we haven't requested yet this
  /// session. The callable refreshes inventory docs server-side (so inventory-
  /// backed lines update via the live stream) and returns data for every part,
  /// which we keep for in-memory enrichment of orphan (manual/BOM) lines.
  void _queueDigiKeyEnrichment(ProcurementPlan plan, {required bool canEdit}) {
    // Only editors (UMD accounts) can invoke the function; skip otherwise.
    if (!canEdit) return;

    final requestsByKey = <String, DigiKeyLookupRequest>{};
    for (final line in plan.lines) {
      if (line.purchaseQty <= 0) continue;
      final key = line.preferredOrderIdentifier.trim();
      if (key.isEmpty) continue;
      if (_digikeyRequestedKeys.contains(key)) continue;
      if (requestsByKey.containsKey(key)) continue;

      final dkPn = line.digikeyPartNumber?.trim();
      final mpn = line.partNumber.trim();
      requestsByKey[key] = DigiKeyLookupRequest(
        key: key,
        dkPn: (dkPn != null && dkPn.isNotEmpty) ? dkPn : null,
        mpn: mpn.isNotEmpty ? mpn : null,
        inventoryDocId: line.inventoryDocId,
      );
    }

    if (requestsByKey.isEmpty) return;

    _digikeyRequestedKeys.addAll(requestsByKey.keys);
    final requests = requestsByKey.values.toList(growable: false);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _digikeyLookupInFlight = true);
      final results = await _digikeyApi.lookupParts(requests);
      if (!mounted) return;
      setState(() {
        _digikeyInfoByKey.addAll(results);
        _digikeyLookupInFlight = false;
      });
    });
  }

  /// Fills missing line fields from DigiKey results we've already fetched. Only
  /// gaps are filled — curated inventory data is never overwritten here (the
  /// authoritative refresh happens server-side on the inventory doc).
  ProcurementPlan _applyDigiKeyEnrichment(ProcurementPlan plan) {
    if (_digikeyInfoByKey.isEmpty) return plan;

    final lines = plan.lines.map((line) {
      final info = _digikeyInfoByKey[line.preferredOrderIdentifier.trim()];
      if (info == null || !info.hasData) return line;

      final currentDk = line.digikeyPartNumber?.trim() ?? '';
      final currentLink = line.vendorLink?.trim() ?? '';
      return line.copyWith(
        digikeyPartNumber:
            currentDk.isEmpty && (info.digiKeyPartNumber?.isNotEmpty ?? false)
                ? info.digiKeyPartNumber
                : line.digikeyPartNumber,
        unitPrice: line.unitPrice ?? info.unitPrice,
        vendorLink:
            currentLink.isEmpty && (info.productUrl?.isNotEmpty ?? false)
                ? info.productUrl
                : line.vendorLink,
        description:
            line.description.trim().isEmpty &&
                    (info.description?.isNotEmpty ?? false)
                ? info.description
                : line.description,
        package:
            line.package.trim().isEmpty &&
                    (info.packageCase?.isNotEmpty ?? false)
                ? info.packageCase
                : line.package,
        digikeyStock: line.digikeyStock ?? info.quantityAvailable,
      );
    }).toList(growable: false);

    return ProcurementPlan(lines: lines, issues: plan.issues);
  }

  void _queueDigiKeyPartNumberBackfill(
    ProcurementPlan plan,
    QuerySnapshot<Map<String, dynamic>> inventory, {
    required bool canEdit,
  }) {
    if (!canEdit) return;

    final docsById = {for (final doc in inventory.docs) doc.id: doc};
    final updates = <String, String>{};
    for (final line in plan.lines) {
      final docId = line.inventoryDocId;
      final digiKeyPn = line.digikeyPartNumber?.trim() ?? '';
      if (docId == null || digiKeyPn.isEmpty) continue;

      final data = docsById[docId]?.data();
      final current =
          data?[FirestoreFields.digiKeyPartNumber]?.toString().trim() ?? '';
      if (current.isNotEmpty) continue;

      final queueKey = '$docId::$digiKeyPn';
      if (!_digikeyPnBackfillKeys.add(queueKey)) continue;
      updates[docId] = digiKeyPn;
    }

    if (updates.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_saveDigiKeyPartNumberBackfill(updates));
    });
  }

  Future<void> _saveDigiKeyPartNumberBackfill(
    Map<String, String> updates,
  ) async {
    if (updates.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final collection = FirebaseFirestore.instance.collection(
      FirestoreCollections.inventory,
    );
    for (final entry in updates.entries) {
      batch.update(collection.doc(entry.key), {
        FirestoreFields.digiKeyPartNumber: entry.value,
        FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
      });
    }

    try {
      await batch.commit();
    } catch (_) {
      // Firestore rules may reject this for read-only users; the planner still works.
    }
  }

  Future<void> _openDigiKeySearch(ProcurementLine line) async {
    final query = [
      line.partNumber,
      line.description,
      line.value,
      line.package,
    ].where((value) => value.trim().isNotEmpty).join(' ');
    if (query.isEmpty) return;

    final uri = Uri.parse(DigiKeyPartResolver.searchUrl(query));
    if (kIsWeb) {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  ProcurementPlan _applyPlannerOverrides(ProcurementPlan plan) {
    final adjustedLines = <ProcurementLine>[];
    for (final line in plan.lines) {
      final key = _plannerLineKey(line);
      if (_deletedPlannerLineKeys.contains(key)) continue;

      var adjusted = line;
      if (_purchaseQtyOverrides.containsKey(key)) {
        final qty = _purchaseQtyOverrides[key]!.clamp(0, 999999).toInt();
        adjusted = adjusted.copyWith(purchaseQty: qty);
      }
      if (_digikeyPnOverrides.containsKey(key)) {
        final value = _digikeyPnOverrides[key]!.trim();
        adjusted = adjusted.copyWith(
          digikeyPartNumber: value.isEmpty ? null : value,
        );
      }
      adjustedLines.add(adjusted);
    }
    return ProcurementPlan(lines: adjustedLines, issues: plan.issues);
  }

  String _plannerLineKey(ProcurementLine line) {
    final boards = line.boardNames.map((b) => b.toLowerCase()).toList()..sort();
    return [
      line.source.name,
      line.inventoryDocId ?? '',
      line.partNumber.toLowerCase(),
      line.description.toLowerCase(),
      boards.join('|'),
    ].join('::');
  }

  String _lowStockLineKey(ProcurementLine line) {
    final inventoryId = line.inventoryDocId?.trim() ?? '';
    final partId =
        inventoryId.isNotEmpty
            ? 'inventory::$inventoryId'
            : 'line::${_plannerLineKey(line)}';
    return [
      partId,
      'required:${line.requiredQty}',
      'remaining:${line.remainingAfterRequired}',
      'target:${line.lowStockThreshold ?? ''}',
    ].join('::');
  }

  void _dismissLowStockLine(ProcurementLine line) {
    setState(() {
      _dismissedLowStockLineKeys.add(_lowStockLineKey(line));
    });
    unawaited(_saveCartState());
  }

  void _restoreDismissedLowStock() {
    setState(() {
      _dismissedLowStockLineKeys.clear();
    });
    unawaited(_saveCartState());
  }

  Future<void> _showPurchaseQtyDialog(ProcurementLine line) async {
    final controller = TextEditingController(text: '${line.purchaseQty}');
    final result = await showDialog<int>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Purchase Quantity: ${line.partNumber}'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Qty to buy',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 0),
                child: const Text('Set 0'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(
                      ctx,
                      int.tryParse(controller.text.trim()),
                    ),
                child: const Text('Set'),
              ),
            ],
          ),
    );
    controller.dispose();

    if (result == null) return;
    setState(() {
      _purchaseQtyOverrides[_plannerLineKey(line)] =
          result.clamp(0, 999999).toInt();
    });
    unawaited(_saveCartState());
  }

  Future<void> _showDigiKeyPnDialog(ProcurementLine line) async {
    final controller = TextEditingController(
      text: line.digikeyPartNumber?.trim() ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('DigiKey PN: ${line.partNumber}'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'DigiKey part number',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('Clear'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    controller.dispose();

    if (result == null) return;
    setState(() {
      _digikeyPnOverrides[_plannerLineKey(line)] = result.trim();
    });
    unawaited(_saveCartState());
    unawaited(_saveDigiKeyPartNumberOverride(line, result.trim()));
  }

  Future<void> _saveDigiKeyPartNumberOverride(
    ProcurementLine line,
    String value,
  ) async {
    final docId = line.inventoryDocId;
    if (line.source != ProcurementLineSource.inventory || docId == null) {
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection(FirestoreCollections.inventory)
          .doc(docId);
      if (value.isEmpty) {
        await docRef.update({
          FirestoreFields.digiKeyPartNumber: FieldValue.delete(),
          FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.update({
          FirestoreFields.digiKeyPartNumber: value,
          FirestoreFields.lastUpdated: FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Keep the local override even if the user cannot write inventory.
    }
  }

  void _deletePlannerLine(ProcurementLine line) {
    setState(() {
      if (line.source == ProcurementLineSource.manual) {
        final idx = _manualLines.indexWhere(
          (manual) =>
              manual.partNumber.trim().toLowerCase() ==
                  line.partNumber.trim().toLowerCase() &&
              manual.description.trim().toLowerCase() ==
                  line.description.trim().toLowerCase() &&
              manual.quantity == line.requiredQty,
        );
        if (idx >= 0) {
          _manualLines.removeAt(idx);
          return;
        }
      }
      _deletedPlannerLineKeys.add(_plannerLineKey(line));
    });
    unawaited(_saveCartState());
  }

  String _sourceLabel(ProcurementLineSource source) {
    switch (source) {
      case ProcurementLineSource.inventory:
        return 'Inventory';
      case ProcurementLineSource.bomFallback:
        return 'BOM fallback';
      case ProcurementLineSource.manual:
        return 'Manual';
    }
  }

  List<BoardOrderRequest> _toBoardOrders(List<BoardDoc> boards) {
    final byId = {for (final b in boards) b.id: b};
    return _boardCartQtyById.entries
        .where((e) => e.value > 0 && byId[e.key] != null)
        .map((e) => BoardOrderRequest(board: byId[e.key]!, quantity: e.value))
        .toList();
  }

  void _clearCart() {
    setState(() {
      _boardCartQtyById.clear();
      _manualLines.clear();
      _purchaseQtyOverrides.clear();
      _digikeyPnOverrides.clear();
      _deletedPlannerLineKeys.clear();
      _dismissedLowStockLineKeys.clear();
    });
    unawaited(_saveCartState());
  }

  void _removeBoardFromCart(String boardId) {
    setState(() {
      _boardCartQtyById.remove(boardId);
    });
    unawaited(_saveCartState());
  }

  void _removeManualLineAt(int index) {
    if (index < 0 || index >= _manualLines.length) return;
    setState(() {
      _manualLines.removeAt(index);
    });
    unawaited(_saveCartState());
  }

  Future<void> _showBoardCartDialog(
    BuildContext context,
    BoardDoc board,
  ) async {
    int qty = _boardCartQtyById[board.id] ?? 1;
    final result = await showDialog<int>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setLocal) => AlertDialog(
                  title: Text('Cart Quantity: ${board.name}'),
                  content: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: qty > 0 ? () => setLocal(() => qty--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text('$qty', style: const TextStyle(fontSize: 22)),
                      IconButton(
                        onPressed: () => setLocal(() => qty++),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, -1),
                      child: const Text('Remove'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, qty),
                      child: const Text('Set'),
                    ),
                  ],
                ),
          ),
    );

    if (result == null) return;
    setState(() {
      if (result <= 0) {
        _boardCartQtyById.remove(board.id);
      } else {
        _boardCartQtyById[board.id] = result;
      }
    });
    unawaited(_saveCartState());
  }

  Future<void> _showAddManualLineDialog() async {
    final partNumber = TextEditingController();
    final digikeyPn = TextEditingController();
    final description = TextEditingController();
    final vendorLink = TextEditingController();
    int qty = 1;

    final added = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setLocal) => AlertDialog(
                  title: const Text('Add Custom Cart Line'),
                  content: SizedBox(
                    width: 500,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: partNumber,
                          decoration: const InputDecoration(
                            labelText: 'Part # / MPN',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: digikeyPn,
                          decoration: const InputDecoration(
                            labelText: 'DigiKey Part # (optional)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: description,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: vendorLink,
                          decoration: const InputDecoration(
                            labelText: 'Vendor Link (optional)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Qty to order'),
                            const Spacer(),
                            IconButton(
                              onPressed:
                                  qty > 1 ? () => setLocal(() => qty--) : null,
                              icon: const Icon(Icons.remove),
                            ),
                            Text('$qty'),
                            IconButton(
                              onPressed: () => setLocal(() => qty++),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Add'),
                    ),
                  ],
                ),
          ),
    );

    if (added != true) return;
    final pn = partNumber.text.trim();
    final dk = digikeyPn.text.trim();
    if (pn.isEmpty && dk.isEmpty) {
      _showInfo('Enter at least Part # or DigiKey Part #.');
      return;
    }
    final desc = description.text.trim();
    setState(() {
      _addOrMergeManualLine(
        ManualProcurementLine(
          partNumber: pn.isEmpty ? dk : pn,
          digikeyPartNumber: dk.isEmpty ? null : dk,
          description: desc.isEmpty ? (pn.isEmpty ? dk : pn) : desc,
          quantity: qty,
          vendorLink:
              vendorLink.text.trim().isEmpty ? null : vendorLink.text.trim(),
        ),
      );
    });
    unawaited(_saveCartState());
  }

  Future<void> _showAddInventoryLineDialog(
    QuerySnapshot<Map<String, dynamic>> inventory,
  ) async {
    final docs =
        inventory.docs.toList()..sort((a, b) {
          final ap =
              (a.data()[FirestoreFields.partNumber] ?? '')
                  .toString()
                  .toLowerCase();
          final bp =
              (b.data()[FirestoreFields.partNumber] ?? '')
                  .toString()
                  .toLowerCase();
          return ap.compareTo(bp);
        });

    if (docs.isEmpty) {
      _showInfo('Inventory is empty.');
      return;
    }

    String selectedId = docs.first.id;
    int qty = 1;
    final options =
        docs
            .map(
              (doc) =>
                  SearchablePartPicker.inventoryDocToOption(doc.id, doc.data()),
            )
            .toList();
    final added = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setLocal) => AlertDialog(
                  title: const Text('Add Inventory Item To Cart'),
                  content: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SearchablePartPicker(
                          key: ValueKey(selectedId),
                          currentValue: selectedId,
                          optionsProvider: (_) async => options,
                          rowData: const <String, dynamic>{},
                          colorScheme: Theme.of(ctx).colorScheme,
                          outlined: true,
                          labelText: 'Inventory Item',
                          autoOpen: false,
                          onChanged: (v) {
                            if (v == null || v.isEmpty) return;
                            setLocal(() => selectedId = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        _InventorySelectionPreview(
                          data:
                              docs
                                  .firstWhere((doc) => doc.id == selectedId)
                                  .data(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Extra qty to order'),
                            const Spacer(),
                            IconButton(
                              onPressed:
                                  qty > 1 ? () => setLocal(() => qty--) : null,
                              icon: const Icon(Icons.remove),
                            ),
                            Text('$qty'),
                            IconButton(
                              onPressed: () => setLocal(() => qty++),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Add'),
                    ),
                  ],
                ),
          ),
    );

    if (added != true) return;
    final doc = docs.firstWhere((d) => d.id == selectedId);
    final data = doc.data();
    final partNumber =
        (data[FirestoreFields.partNumber] ?? '').toString().trim();
    final description =
        (data[FirestoreFields.description] ?? '').toString().trim();
    final vendorLink =
        (data[FirestoreFields.vendorLink] ?? '').toString().trim();

    setState(() {
      _addOrMergeManualLine(
        ManualProcurementLine(
          partNumber: partNumber.isEmpty ? doc.id : partNumber,
          digikeyPartNumber: ProcurementPlannerService.extractDigiKeyPartNumber(
            vendorLink,
            fallbackPartNumber:
                (data[FirestoreFields.digiKeyPartNumber] ?? partNumber)
                    .toString(),
          ),
          description: description.isEmpty ? partNumber : description,
          quantity: qty,
          vendorLink: vendorLink.isEmpty ? null : vendorLink,
          partType: (data[FirestoreFields.type] ?? '').toString(),
          package: (data[FirestoreFields.package] ?? '').toString(),
        ),
      );
    });
    unawaited(_saveCartState());
  }

  Future<void> _showPasteCartDialog() async {
    final controller = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Paste Cart Data'),
            content: SizedBox(
              width: 620,
              child: TextField(
                controller: controller,
                autofocus: true,
                minLines: 10,
                maxLines: 18,
                decoration: const InputDecoration(
                  labelText: 'Cart rows',
                  hintText:
                      'Paste DigiKey CSV or quick-order lines like "497-15115-1-ND, 3"',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, controller.text),
                icon: const Icon(Icons.content_paste_go_outlined),
                label: const Text('Add To Cart'),
              ),
            ],
          ),
    );
    controller.dispose();

    if (pasted == null) return;
    final lines = CartPasteParser.parse(pasted);
    if (lines.isEmpty) {
      _showInfo('No cart rows found. Paste CSV or quick-order part/qty lines.');
      return;
    }

    setState(() {
      for (final line in lines) {
        _addOrMergeManualLine(line);
      }
    });
    unawaited(_saveCartState());
    _showInfo('Added ${lines.length} pasted cart line(s).');
  }

  void _addOrMergeManualLine(ManualProcurementLine line) {
    final idx = _manualLines.indexWhere((existing) {
      return existing.partNumber.trim().toLowerCase() ==
              line.partNumber.trim().toLowerCase() &&
          (existing.digikeyPartNumber ?? '').trim().toLowerCase() ==
              (line.digikeyPartNumber ?? '').trim().toLowerCase() &&
          existing.description.trim().toLowerCase() ==
              line.description.trim().toLowerCase() &&
          (existing.vendorLink ?? '').trim().toLowerCase() ==
              (line.vendorLink ?? '').trim().toLowerCase();
    });

    if (idx < 0) {
      _manualLines.add(line);
      return;
    }

    final existing = _manualLines[idx];
    _manualLines[idx] = ManualProcurementLine(
      partNumber: existing.partNumber,
      digikeyPartNumber: existing.digikeyPartNumber,
      description: existing.description,
      quantity: existing.quantity + line.quantity,
      vendorLink: existing.vendorLink,
      partType: existing.partType ?? line.partType,
      package: existing.package ?? line.package,
      boardLabel: existing.boardLabel,
    );
  }

  void _copyDigiKeyCsv(ProcurementPlan plan) async {
    final csv = plan.toDigiKeyCsv();
    await Clipboard.setData(ClipboardData(text: csv));
    _showInfo('Copied DigiKey CSV (${plan.exportableLines.length} lines).');
  }

  void _copyQuickOrder(ProcurementPlan plan) async {
    final text = plan.toQuickOrderText();
    await Clipboard.setData(ClipboardData(text: text));
    _showInfo('Copied quick-order text.');
  }

  void _showInfo(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));
  }

  Future<void> _makeBoards(
    BuildContext context,
    BoardDoc board,
    int qty,
    BoardBuildService buildService,
    QuerySnapshot<Map<String, dynamic>> inventory,
  ) async {
    final activeBomCount = board.bom.where((line) => !line.ignored).length;
    if (activeBomCount == 0) {
      _showInfo('This board has no active BOM lines to build.');
      return;
    }

    var selections = <int, BoardBuildLineSelection>{};
    var preview = await buildService.previewBuild(
      board: board,
      quantity: qty,
      inventorySnapshot: inventory,
    );

    if (!context.mounted) return;

    if (preview.issues.isNotEmpty) {
      final resolved = await showDialog<Map<int, BoardBuildLineSelection>>(
        context: context,
        builder:
            (ctx) => _BoardBuildPrepDialog(
              board: board,
              quantity: qty,
              buildService: buildService,
              inventory: inventory,
            ),
      );
      if (resolved == null || !context.mounted) return;

      selections = resolved;
      preview = await buildService.previewBuild(
        board: board,
        quantity: qty,
        lineSelections: selections,
        inventorySnapshot: inventory,
      );
      if (preview.issues.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resolve each missing line with a substitute or mark it skipped before building.',
            ),
            backgroundColor: Colors.red,
            showCloseIcon: true,
          ),
        );
        return;
      }
    }

    final skippedCount = preview.skippedLines.length;
    final consumedLineCount = preview.consumedByDocId.length;
    final substituteCount =
        selections.values
            .where(
              (selection) =>
                  !selection.skip &&
                  (selection.inventoryDocId?.trim().isNotEmpty ?? false),
            )
            .length;

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Make $qty x ${board.name}?'),
            content: Text(
              'This will subtract parts from $consumedLineCount inventory item(s).'
              '${substituteCount > 0 ? '\n\nManual substitutes: $substituteCount line(s).' : ''}'
              '${skippedCount > 0 ? '\n\nSkipped BOM lines: $skippedCount.' : ''}'
              '\n\nThis action can be undone from the History page.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Make Boards'),
              ),
            ],
          ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await buildService.makeBoards(
        board: board,
        quantity: qty,
        lineSelections: selections,
        inventorySnapshot: inventory,
      );
      if (!context.mounted) return;
      final skippedMsg =
          skippedCount == 0 ? '' : ' Skipped $skippedCount BOM line(s).';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Made $qty x ${board.name}.$skippedMsg'),
          showCloseIcon: true,
        ),
      );
    } on BoardBuildException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
          showCloseIcon: true,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to make board: $e'),
          backgroundColor: Colors.red,
          showCloseIcon: true,
        ),
      );
    }
  }
}

class _InventorySelectionPreview extends StatelessWidget {
  final Map<String, dynamic> data;

  const _InventorySelectionPreview({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final part = (data[FirestoreFields.partNumber] ?? '').toString();
    final description = (data[FirestoreFields.description] ?? '').toString();
    final type = (data[FirestoreFields.type] ?? '').toString();
    final value = (data[FirestoreFields.value] ?? '').toString();
    final package = (data[FirestoreFields.package] ?? '').toString();
    final qty = (data[FirestoreFields.qty] as num?)?.toInt() ?? 0;
    final pieces = [
      type,
      value,
      package,
    ].where((piece) => piece.trim().isNotEmpty).join(' / ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            part.isEmpty ? '(no part #)' : part,
            style: const TextStyle(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          if (description.isNotEmpty)
            Text(
              description,
              style: TextStyle(color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            [if (pieces.isNotEmpty) pieces, 'Stock $qty'].join(' - '),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BoardBuildPrepDialog extends StatefulWidget {
  final BoardDoc board;
  final int quantity;
  final BoardBuildService buildService;
  final QuerySnapshot<Map<String, dynamic>> inventory;

  const _BoardBuildPrepDialog({
    required this.board,
    required this.quantity,
    required this.buildService,
    required this.inventory,
  });

  @override
  State<_BoardBuildPrepDialog> createState() => _BoardBuildPrepDialogState();
}

class _BoardBuildPrepDialogState extends State<_BoardBuildPrepDialog> {
  late final List<QueryDocumentSnapshot<Map<String, dynamic>>> _inventoryDocs;
  final Map<int, BoardBuildLineSelection> _selections =
      <int, BoardBuildLineSelection>{};
  late Future<BoardBuildPreview> _previewFuture;

  @override
  void initState() {
    super.initState();
    _inventoryDocs =
        widget.inventory.docs.toList()..sort((a, b) {
          final aPart =
              (a.data()[FirestoreFields.partNumber] ?? '')
                  .toString()
                  .toLowerCase();
          final bPart =
              (b.data()[FirestoreFields.partNumber] ?? '')
                  .toString()
                  .toLowerCase();
          return aPart.compareTo(bPart);
        });
    _refreshPreview();
  }

  void _refreshPreview() {
    _previewFuture = widget.buildService.previewBuild(
      board: widget.board,
      quantity: widget.quantity,
      lineSelections: _selections,
      inventorySnapshot: widget.inventory,
    );
  }

  void _setSkip(int lineIndex, bool skip) {
    setState(() {
      final current = _selections[lineIndex] ?? const BoardBuildLineSelection();
      _selections[lineIndex] = BoardBuildLineSelection(
        inventoryDocId: skip ? null : current.inventoryDocId,
        skip: skip,
      );
      _refreshPreview();
    });
  }

  void _setSubstitute(int lineIndex, String? inventoryDocId) {
    setState(() {
      _selections[lineIndex] = BoardBuildLineSelection(
        inventoryDocId: inventoryDocId,
        skip: false,
      );
      _refreshPreview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Resolve BOM For ${widget.board.name}'),
      content: SizedBox(
        width: 760,
        child: FutureBuilder<BoardBuildPreview>(
          future: _previewFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final preview = snapshot.data!;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantity: ${widget.quantity}. Pick a substitute inventory item or skip each blocked BOM line.',
                    ),
                    const SizedBox(height: 12),
                    if (preview.issues.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          preview.skippedLines.isEmpty
                              ? 'Everything is resolved and ready to build.'
                              : 'All remaining issues are resolved. ${preview.skippedLines.length} line(s) will be skipped.',
                        ),
                      )
                    else
                      ...preview.issues.map((issue) {
                        final selection = _selections[issue.lineIndex];
                        final chosenId =
                            selection?.skip == true
                                ? null
                                : selection?.inventoryDocId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _BoardBuildIssueCard(
                            issue: issue,
                            inventoryDocs: _inventoryDocs,
                            selectedDocId: chosenId,
                            skipped: selection?.skip == true,
                            onSkipChanged:
                                (value) => _setSkip(issue.lineIndex, value),
                            onSubstituteChanged:
                                (value) =>
                                    _setSubstitute(issue.lineIndex, value),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FutureBuilder<BoardBuildPreview>(
          future: _previewFuture,
          builder: (context, snapshot) {
            final canContinue = snapshot.data?.issues.isEmpty == true;
            return FilledButton(
              onPressed:
                  canContinue
                      ? () => Navigator.pop(
                        context,
                        Map<int, BoardBuildLineSelection>.from(_selections),
                      )
                      : null,
              child: const Text('Continue'),
            );
          },
        ),
      ],
    );
  }
}

class _BoardBuildIssueCard extends StatelessWidget {
  final BoardBuildIssue issue;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> inventoryDocs;
  final String? selectedDocId;
  final bool skipped;
  final ValueChanged<bool> onSkipChanged;
  final ValueChanged<String?> onSubstituteChanged;

  const _BoardBuildIssueCard({
    required this.issue,
    required this.inventoryDocs,
    required this.selectedDocId,
    required this.skipped,
    required this.onSkipChanged,
    required this.onSubstituteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final severityColor = switch (issue.kind) {
      BoardBuildIssueKind.unresolved => cs.error,
      BoardBuildIssueKind.ambiguous => cs.secondary,
      BoardBuildIssueKind.insufficientStock => Colors.orange,
    };
    final candidateSummary =
        issue.candidates.isEmpty
            ? null
            : issue.candidates.map(_inventoryLabel).join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withValues(alpha: 0.45)),
        color: severityColor.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            issue.partLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${issue.line.designators} • need ${issue.requiredQty}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            _issueSummary(issue),
            style: TextStyle(color: severityColor, fontWeight: FontWeight.w600),
          ),
          if (candidateSummary != null) ...[
            const SizedBox(height: 6),
            Text(
              'Current matches: $candidateSummary',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          if (skipped)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Substitute inventory item',
                border: OutlineInputBorder(),
                enabled: false,
              ),
              child: Text(
                'Line skipped',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            SearchablePartPicker(
              key: ValueKey('substitute-${issue.lineIndex}'),
              outlined: true,
              autoOpen: false,
              labelText: 'Substitute inventory item',
              currentValue: selectedDocId ?? '',
              colorScheme: cs,
              rowData: {
                FirestoreFields.requiredAttributes:
                    issue.line.requiredAttributes,
              },
              optionsProvider:
                  (_) async =>
                      inventoryDocs
                          .map(
                            (doc) => SearchablePartPicker.inventoryDocToOption(
                              doc.id,
                              doc.data(),
                            ),
                          )
                          .toList(),
              onChanged: (value) {
                onSubstituteChanged(
                  (value == null || value.isEmpty) ? null : value,
                );
              },
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: skipped,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Skip this BOM line'),
            subtitle: const Text(
              'Build the board without consuming inventory for this line.',
            ),
            onChanged: (value) => onSkipChanged(value ?? false),
          ),
        ],
      ),
    );
  }

  static String _issueSummary(BoardBuildIssue issue) {
    return switch (issue.kind) {
      BoardBuildIssueKind.unresolved =>
        'No inventory match found for this BOM line.',
      BoardBuildIssueKind.ambiguous =>
        'Multiple inventory matches found. Choose one or skip it.',
      BoardBuildIssueKind.insufficientStock =>
        'Selected inventory only has ${issue.availableQty} of ${issue.requiredQty} needed.',
    };
  }

  static String _inventoryLabel(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final part = (data[FirestoreFields.partNumber] ?? doc.id).toString().trim();
    final value = (data[FirestoreFields.value] ?? '').toString().trim();
    final package = (data[FirestoreFields.package] ?? '').toString().trim();
    final qty = (data[FirestoreFields.qty] as num?)?.toInt() ?? 0;
    final bits = <String>[part];
    if (value.isNotEmpty) bits.add(value);
    if (package.isNotEmpty) bits.add(package);
    bits.add('stock $qty');
    return bits.join(' - ');
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 16), label: Text('$label: $value'));
  }
}

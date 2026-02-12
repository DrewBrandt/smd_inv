import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/data/inventory_repo.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/models/procurement.dart';
import 'package:smd_inv/models/readiness.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/services/board_build_service.dart';
import 'package:smd_inv/services/procurement_planner_service.dart';
import 'package:smd_inv/services/readiness_calculator.dart';
import 'package:smd_inv/widgets/board_card.dart';

import '../constants/firestore_constants.dart';
import '../data/boards_repo.dart';

typedef Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

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

  final Map<String, int> _boardCartQtyById = <String, int>{};
  final List<ManualProcurementLine> _manualLines = <ManualProcurementLine>[];

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

            final boards =
                snap.data!.map(BoardDoc.fromSnap).toList()..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

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

                if (boards.isEmpty) {
                  return _buildEmptyState(canEdit);
                }

                return Column(
                  children: [
                    if (!canEdit) _buildViewOnlyBanner(),
                    _buildHeader(canEdit, boards.length),
                    const SizedBox(height: 12),
                    _buildProcurementPanel(boards, inventory),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: boards.length,
                        itemBuilder: (context, i) {
                          final b = boards[i];
                          final cartQty = _boardCartQtyById[b.id] ?? 0;
                          return FutureBuilder<Readiness>(
                            future: ReadinessCalculator.calculate(
                              b,
                              inventorySnapshot: inventory,
                            ),
                            builder: (context, readinessSnap) {
                              final r =
                                  readinessSnap.data ??
                                  const Readiness(
                                    buildableQty: 0,
                                    readyPct: 0.0,
                                    shortfalls: [],
                                  );

                              return ImprovedBoardCard(
                                board: b,
                                readiness: r,
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
                                        )
                                        : null,
                              );
                            },
                          );
                        },
                      ),
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

  Widget _buildHeader(bool canEdit, int boardCount) {
    final cs = Theme.of(context).colorScheme;
    final boardCartCount = _boardCartQtyById.values.fold<int>(
      0,
      (total, qty) => total + qty,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        color: cs.surfaceContainer,
      ),
      child: Row(
        children: [
          Text(
            'Boards ($boardCount)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
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
    );
  }

  Widget _buildProcurementPanel(
    List<BoardDoc> boards,
    QuerySnapshot<Map<String, dynamic>> inventory,
  ) {
    final cs = Theme.of(context).colorScheme;
    final boardOrders = _toBoardOrders(boards);
    final hasAnyCartItems = boardOrders.isNotEmpty || _manualLines.isNotEmpty;

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
          if (!hasAnyCartItems) {
            return _buildPlannerPlaceholder();
          }

          if (!planSnap.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final basePlan = planSnap.data!;
          final plan = ProcurementPlannerService.mergeManualLines(
            basePlan,
            _manualLines,
          );
          final orderLines = plan.orderableLines;
          final nonExportable =
              orderLines.where((l) => !l.hasOrderIdentifier).length;
          final totalLinesInCart =
              _boardCartQtyById.length + _manualLines.length;

          return Column(
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
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                    label: Text(
                      '${plan.unresolvedCount} unresolved, ${plan.ambiguousCount} ambiguous',
                    ),
                  ),
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
              if (_boardCartQtyById.isNotEmpty) _buildBoardCartSection(boards),
              if (_manualLines.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildManualLinesSection(),
              ],
              if (plan.issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildIssuesSection(plan),
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

  Widget _buildOrderLinesTable(List<ProcurementLine> lines) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Part')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Pkg')),
          DataColumn(label: Text('Need')),
          DataColumn(label: Text('Stock')),
          DataColumn(label: Text('Buy')),
          DataColumn(label: Text('Source')),
          DataColumn(label: Text('Boards')),
        ],
        rows:
            lines.map((line) {
              final id = line.digikeyPartNumber ?? line.partNumber;
              return DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 250,
                      child: Text(id, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(Text(line.partType.isEmpty ? '-' : line.partType)),
                  DataCell(Text(line.package.isEmpty ? '-' : line.package)),
                  DataCell(Text('${line.requiredQty}')),
                  DataCell(Text('${line.inStockQty}')),
                  DataCell(Text('${line.shortageQty}')),
                  DataCell(Text(_sourceLabel(line.source))),
                  DataCell(
                    SizedBox(
                      width: 220,
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
    );
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
    });
  }

  void _removeBoardFromCart(String boardId) {
    setState(() {
      _boardCartQtyById.remove(boardId);
    });
  }

  void _removeManualLineAt(int index) {
    if (index < 0 || index >= _manualLines.length) return;
    setState(() {
      _manualLines.removeAt(index);
    });
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
      _manualLines.add(
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
                        DropdownButtonFormField<String>(
                          initialValue: selectedId,
                          decoration: const InputDecoration(
                            labelText: 'Inventory Item',
                          ),
                          items:
                              docs.map((doc) {
                                final d = doc.data();
                                final part =
                                    (d[FirestoreFields.partNumber] ?? '')
                                        .toString();
                                final desc =
                                    (d[FirestoreFields.description] ?? '')
                                        .toString();
                                final stock =
                                    (d[FirestoreFields.qty] as num?)?.toInt() ??
                                    0;
                                return DropdownMenuItem<String>(
                                  value: doc.id,
                                  child: Text(
                                    '$part (stock $stock) ${desc.isEmpty ? '' : '- $desc'}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() => selectedId = v);
                          },
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
      _manualLines.add(
        ManualProcurementLine(
          partNumber: partNumber.isEmpty ? doc.id : partNumber,
          digikeyPartNumber: ProcurementPlannerService.extractDigiKeyPartNumber(
            vendorLink,
            fallbackPartNumber: partNumber,
          ),
          description: description.isEmpty ? partNumber : description,
          quantity: qty,
          vendorLink: vendorLink.isEmpty ? null : vendorLink,
          partType: (data[FirestoreFields.type] ?? '').toString(),
          package: (data[FirestoreFields.package] ?? '').toString(),
        ),
      );
    });
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _makeBoards(
    BuildContext context,
    BoardDoc board,
    int qty,
    BoardBuildService buildService,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('Make $qty x ${board.name}?'),
            content: const Text(
              'This will subtract required quantities from inventory.\n\nThis action can be undone from the History page.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );

    if (confirm != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Subtracting parts from inventory...'),
              ],
            ),
          ),
    );

    try {
      await buildService.makeBoards(board: board, quantity: qty);

      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Built $qty x ${board.name}'),
          action: SnackBarAction(
            label: 'View History',
            onPressed: () => context.go('/admin'),
          ),
        ),
      );
    } on BoardBuildException catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
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

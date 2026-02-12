// lib/widgets/improved_board_card.dart
import 'package:flutter/material.dart';
import '../models/board.dart';
import '../models/readiness.dart';

class ImprovedBoardCard extends StatelessWidget {
  final BoardDoc board;
  final Readiness readiness;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback? onAddToCart;
  final int cartQty;
  final Future<void> Function(int qty)? onMake;

  const ImprovedBoardCard({
    super.key,
    required this.board,
    required this.readiness,
    this.canEdit = true,
    required this.onOpen,
    required this.onDuplicate,
    this.onAddToCart,
    this.cartQty = 0,
    required this.onMake,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalCost = readiness.totalCost ?? 0.0;
    final buildableQty = readiness.buildableQty;
    final readyPct = readiness.readyPct;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with image/icon
            Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.65),
                    cs.surfaceContainerHigh,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child:
                  board.imageUrl != null && board.imageUrl!.isNotEmpty
                      ? Image.network(
                        board.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder:
                            (context, error, stackTrace) =>
                                _buildPlaceholderIcon(cs),
                      )
                      : _buildPlaceholderIcon(cs),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            board.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (board.category != null &&
                            board.category!.isNotEmpty)
                          Chip(
                            label: Text(
                              board.category!,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),

                    if (board.description != null &&
                        board.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        board.description!,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        _buildStat(
                          icon: Icons.widgets_outlined,
                          label: 'Parts',
                          value: '${board.bom.length}',
                          color: cs.primary,
                        ),
                        const SizedBox(width: 16),
                        _buildStat(
                          icon: Icons.price_check_outlined,
                          label: 'Cost',
                          value:
                              totalCost > 0
                                  ? '\$${totalCost.toStringAsFixed(2)}'
                                  : '–',
                          color: cs.tertiary,
                        ),
                        const SizedBox(width: 16),
                        _buildStat(
                          icon: Icons.inventory_outlined,
                          label: 'Buildable',
                          value: buildableQty > 0 ? '$buildableQty×' : '0×',
                          color: buildableQty > 0 ? Colors.green : Colors.red,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Readiness indicator
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Inventory Readiness',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${(readyPct * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getReadinessColor(readyPct),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: readyPct,
                            minHeight: 8,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              _getReadinessColor(readyPct),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Shortfalls
                    if (readiness.shortfalls.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cs.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  size: 16,
                                  color: cs.error,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Missing ${readiness.shortfalls.length} part(s)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...readiness.shortfalls
                                .take(
                                  readiness.shortfalls.length > 3
                                      ? 2
                                      : readiness.shortfalls.length,
                                )
                                .map(
                                  (s) => Padding(
                                    padding: const EdgeInsets.only(
                                      left: 20,
                                      top: 2,
                                    ),
                                    child: Text(
                                      '• ${s.part}: ${s.qty} needed',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ),
                            if (readiness.shortfalls.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 20,
                                  top: 2,
                                ),
                                child: Text(
                                  '• ... and ${readiness.shortfalls.length - 2} more',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onErrorContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onOpen,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                canEdit && buildableQty > 0 && onMake != null
                                    ? () => _showMakeDialog(context)
                                    : null,
                            icon: const Icon(Icons.construction, size: 16),
                            label: const Text('Make'),
                          ),
                        ),
                        _CartButton(onPressed: onAddToCart, count: cartQty),
                        IconButton(
                          onPressed: canEdit ? onDuplicate : null,
                          icon: const Icon(Icons.content_copy, size: 18),
                          tooltip: 'Duplicate',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderIcon(ColorScheme cs) {
    return Center(
      child: Icon(
        Icons.memory,
        size: 48,
        color: cs.primary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10)),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getReadinessColor(double pct) {
    if (pct >= 0.9) return Colors.green;
    if (pct >= 0.7) return Colors.lightGreen;
    if (pct >= 0.5) return Colors.orange;
    return Colors.red;
  }

  Future<void> _showMakeDialog(BuildContext context) async {
    int qty = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('Make ${board.name}'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'You can build up to ${readiness.buildableQty} board(s).',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text('Quantity:'),
                          const Spacer(),
                          IconButton(
                            onPressed:
                                qty > 1 ? () => setState(() => qty--) : null,
                            icon: const Icon(Icons.remove),
                          ),
                          Text(
                            '$qty',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed:
                                qty < readiness.buildableQty
                                    ? () => setState(() => qty++)
                                    : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
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
          ),
    );

    if (confirmed == true) {
      onMake?.call(qty);
    }
  }
}

class _CartButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final int count;

  const _CartButton({required this.onPressed, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: count > 0 ? 'In cart: $count' : 'Add to purchase cart',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: onPressed,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
          ),
          if (count > 0)
            Positioned(
              right: 3,
              top: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

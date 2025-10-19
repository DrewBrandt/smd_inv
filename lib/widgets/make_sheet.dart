import 'package:flutter/material.dart';

/// Shows the qty picker. Returns the confirmed quantity, or null if cancelled.
Future<int?> showMakeSheet(BuildContext context, {required int maxQty}) {
  int qty = (maxQty > 0) ? 1 : 0;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder:
        (c) => StatefulBuilder(
          builder: (c, set) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('Quantity'),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: qty > 0 ? () => set(() => qty = (qty - 1).clamp(0, maxQty)) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  IconButton(
                    onPressed: qty < maxQty ? () => set(() => qty = (qty + 1).clamp(0, maxQty)) : null,
                    icon: const Icon(Icons.add),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: qty > 0 ? () => Navigator.pop(c, qty) : null, child: const Text('Confirm')),
                ],
              ),
            );
          },
        ),
  );
}
